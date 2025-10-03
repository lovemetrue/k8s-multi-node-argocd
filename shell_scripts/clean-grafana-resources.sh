#!/bin/bash
#
# Kubernetes Monitoring Stack Cleanup Script
# Fixed version without timeouts and with namespace error handling
#

set -euo pipefail

readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOCKFILE="/var/run/${SCRIPT_NAME}.lock"

# Configuration
readonly LOG_FILE="/var/log/k8s_monitoring_cleanup.log"
readonly DRY_RUN=${DRY_RUN:-false}
readonly FORCE=${FORCE:-false}
readonly REMOVE_FINALIZERS=${REMOVE_FINALIZERS:-true}

# Color codes for logging
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Global variables
declare -g CLEANUP_START_TIME
declare -g ERROR_OCCURRED=false
declare -g KUBECTL_AVAILABLE=false

# Signal handlers
trap 'cleanup_and_exit 130' SIGINT
trap 'cleanup_and_exit 143' SIGTERM
trap 'handle_error ${LINENO}' ERR

main() {
    local operation="${1:-cleanup}"
    
    case "${operation}" in
        "cleanup")
            run_cleanup
            ;;
        "dry-run")
            DRY_RUN=true
            run_cleanup
            ;;
        "status")
            check_remaining_resources
            ;;
        "list-finalizers")
            list_resources_with_finalizers
            ;;
        *)
            show_usage
            exit 1
            ;;
    esac
}

run_cleanup() {
    log_info "Starting Kubernetes monitoring cleanup process"
    log_warning "WARNING: This will delete all Prometheus and Grafana resources!"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "DRY RUN MODE - No resources will be actually deleted"
    fi
    
    if [[ "${REMOVE_FINALIZERS}" == "true" ]]; then
        log_info "Finalizers removal: ENABLED"
    else
        log_warning "Finalizers removal: DISABLED (resources with finalizers may not be deleted)"
    fi
    
    if [[ "${FORCE}" != "true" ]]; then
        if ! confirm_action; then
            log_info "Cleanup cancelled by user"
            exit 0
        fi
    fi
    
    CLEANUP_START_TIME=$(date +%s)
    
    check_prerequisites
    acquire_lock
    check_kubectl_access
    
    log_info "Beginning cleanup operations..."
    
    delete_prometheus_crds
    delete_rbac_resources
    delete_namespaced_resources_bulk
    delete_webhooks_and_apiservices
    cleanup_monitoring_namespace
    delete_remaining_resources
    
    if [[ "${ERROR_OCCURRED}" == "true" ]]; then
        log_error "Cleanup completed with errors"
        exit 1
    else
        log_success "Cleanup completed successfully"
        check_remaining_resources
    fi
}

check_prerequisites() {
    log_info "Checking prerequisites"
    
    # Check kubectl availability
    if command -v kubectl >/dev/null 2>&1; then
        KUBECTL_AVAILABLE=true
        log_success "kubectl is available"
    else
        log_error "kubectl is not available"
        exit 1
    fi
    
    # Check if we're connected to a cluster
    if ! kubectl cluster-info >/dev/null 2>&1; then
        log_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

acquire_lock() {
    log_info "Acquiring cleanup lock"
    
    local lock_dir=$(dirname "${LOCKFILE}")
    if [[ ! -d "${lock_dir}" ]]; then
        mkdir -p "${lock_dir}"
    fi
    
    if [[ -f "${LOCKFILE}" ]]; then
        local lock_pid
        lock_pid=$(<"${LOCKFILE}")
        if kill -0 "${lock_pid}" 2>/dev/null; then
            log_error "Cleanup already running with PID: ${lock_pid}"
            exit 1
        else
            log_warning "Stale lock file found, removing"
            rm -f "${LOCKFILE}"
        fi
    fi
    
    echo $$ > "${LOCKFILE}"
    log_success "Lock acquired"
}

confirm_action() {
    echo
    log_warning "=== DANGER ZONE ==="
    log_warning "This operation will:"
    log_warning "• Delete ALL Prometheus CRDs"
    log_warning "• Delete ALL Grafana instances"
    log_warning "• Remove ALL related RBAC resources"
    log_warning "• Cleanup monitoring namespace"
    if [[ "${REMOVE_FINALIZERS}" == "true" ]]; then
        log_warning "• Remove Argo CD finalizers from resources"
    fi
    log_warning "• This operation is IRREVERSIBLE!"
    echo
    
    read -p "Are you absolutely sure you want to continue? (yes/NO): " -r confirmation
    case "${confirmation}" in
        [yY][eE][sS]|[yY])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

check_kubectl_access() {
    log_info "Checking Kubernetes cluster access"
    
    local cluster_info
    if cluster_info=$(kubectl cluster-info 2>/dev/null); then
        log_success "Connected to Kubernetes cluster"
        log_debug "Cluster info: $(echo "${cluster_info}" | head -1)"
    else
        log_error "Failed to connect to Kubernetes cluster"
        exit 1
    fi
    
    # Check if we have sufficient permissions
    if ! kubectl auth can-i delete crd >/dev/null 2>&1; then
        log_error "Insufficient permissions to delete CRDs"
        exit 1
    fi
    
    if [[ "${REMOVE_FINALIZERS}" == "true" ]]; then
        if ! kubectl auth can-i patch crd >/dev/null 2>&1; then
            log_error "Insufficient permissions to patch CRDs (needed for finalizer removal)"
            exit 1
        fi
    fi
    
    log_success "Cluster access check passed"
}

namespace_exists() {
    local namespace="$1"
    kubectl get namespace "$namespace" >/dev/null 2>&1
}

remove_finalizers() {
    local resource_type="$1"
    local resource_name="$2"
    local namespace="${3:-}"
    
    local namespace_arg=""
    if [[ -n "${namespace}" ]]; then
        if ! namespace_exists "${namespace}"; then
            log_debug "Namespace ${namespace} does not exist, skipping finalizer removal"
            return 0
        fi
        namespace_arg="-n ${namespace}"
    fi
    
    # Check if resource exists and has finalizers
    if ! kubectl get ${namespace_arg} "${resource_type}" "${resource_name}" >/dev/null 2>&1; then
        return 0
    fi
    
    local finalizers
    finalizers=$(kubectl get ${namespace_arg} "${resource_type}" "${resource_name}" -o jsonpath='{.metadata.finalizers}' 2>/dev/null || echo "")
    
    if [[ -n "${finalizers}" && "${finalizers}" != "null" && "${finalizers}" != "[]" ]]; then
        log_info "Removing finalizers from ${resource_type}/${resource_name}${namespace_arg:+/${namespace}}"
        log_debug "Finalizers: ${finalizers}"
        
        if [[ "${DRY_RUN}" != "true" ]]; then
            if kubectl patch ${namespace_arg} "${resource_type}" "${resource_name}" \
                --type=json \
                --patch='[{"op": "remove", "path": "/metadata/finalizers"}]'; then
                log_success "Removed finalizers from ${resource_type}/${resource_name}"
            else
                log_error "Failed to remove finalizers from ${resource_type}/${resource_name}"
                return 1
            fi
        else
            log_info "DRY RUN: Would remove finalizers from ${resource_type}/${resource_name}${namespace_arg:+/${namespace}}"
        fi
    fi
    
    return 0
}

delete_resource_with_finalizers() {
    local resource_type="$1"
    local resource_name="$2"
    local namespace="${3:-}"
    
    local namespace_arg=""
    if [[ -n "${namespace}" ]]; then
        if ! namespace_exists "${namespace}"; then
            log_debug "Namespace ${namespace} does not exist, skipping deletion"
            return 0
        fi
        namespace_arg="-n ${namespace}"
    fi
    
    # Remove finalizers first if enabled
    if [[ "${REMOVE_FINALIZERS}" == "true" ]]; then
        if ! remove_finalizers "${resource_type}" "${resource_name}" "${namespace}"; then
            ERROR_OCCURRED=true
            return 1
        fi
    fi
    
    # Now delete the resource
    log_info "Deleting ${resource_type}: ${resource_name}${namespace_arg:+/${namespace}}"
    
    if [[ "${DRY_RUN}" != "true" ]]; then
        if kubectl delete ${namespace_arg} "${resource_type}" "${resource_name}" \
            --ignore-not-found=true; then
            log_success "Deleted ${resource_type}: ${resource_name}${namespace_arg:+/${namespace}}"
        else
            log_error "Failed to delete ${resource_type}: ${resource_name}${namespace_arg:+/${namespace}}"
            
            # If deletion failed due to finalizers, try to remove them and retry
            if [[ "${REMOVE_FINALIZERS}" == "true" ]]; then
                log_info "Retrying deletion after finalizer removal..."
                remove_finalizers "${resource_type}" "${resource_name}" "${namespace}"
                if kubectl delete ${namespace_arg} "${resource_type}" "${resource_name}" \
                    --ignore-not-found=true; then
                    log_success "Deleted ${resource_type}: ${resource_name}${namespace_arg:+/${namespace}} after retry"
                else
                    ERROR_OCCURRED=true
                    return 1
                fi
            else
                ERROR_OCCURRED=true
                return 1
            fi
        fi
    else
        log_info "DRY RUN: Would delete ${resource_type}: ${resource_name}${namespace_arg:+/${namespace}}"
    fi
    
    return 0
}

delete_prometheus_crds() {
    log_info "Step 1: Deleting Prometheus CRDs"
    
    local crds=(
        "alertmanagerconfigs.monitoring.coreos.com"
        "alertmanagers.monitoring.coreos.com"
        "podmonitors.monitoring.coreos.com"
        "probes.monitoring.coreos.com"
        "prometheusagents.monitoring.coreos.com"
        "prometheuses.monitoring.coreos.com"
        "prometheusrules.monitoring.coreos.com"
        "scrapeconfigs.monitoring.coreos.com"
        "servicemonitors.monitoring.coreos.com"
        "thanosrulers.monitoring.coreos.com"
    )
    
    for crd in "${crds[@]}"; do
        if kubectl get crd "${crd}" >/dev/null 2>&1; then
            delete_resource_with_finalizers "crd" "${crd}"
        else
            log_debug "CRD not found: ${crd}"
        fi
    done
}

delete_resources_by_type_and_pattern() {
    local resource_type="$1"
    local namespace="$2"
    local pattern="$3"
    
    # Проверяем, что все аргументы переданы
    if [[ -z "${resource_type}" || -z "${namespace}" || -z "${pattern}" ]]; then
        log_error "delete_resources_by_type_and_pattern: missing arguments"
        return 1
    fi
    
    # Проверяем существование namespace
    if ! namespace_exists "${namespace}"; then
        log_debug "Namespace ${namespace} does not exist, skipping"
        return 0
    fi
    
    local resources
    resources=$(kubectl -n "${namespace}" get "${resource_type}" --no-headers -o custom-columns=":metadata.name" 2>/dev/null | \
        grep -E "${pattern}" || true)
    
    if [[ -n "${resources}" ]]; then
        while IFS= read -r resource; do
            delete_resource_with_finalizers "${resource_type}" "${resource}" "${namespace}"
        done <<< "${resources}"
    fi
}

delete_rbac_resources() {
    log_info "Step 2: Deleting RBAC resources"
    
    delete_cluster_roles
    delete_cluster_role_bindings
    delete_namespaced_rbac
}

delete_cluster_roles() {
    log_info "Deleting cluster roles"
    
    local cluster_roles
    cluster_roles=$(kubectl get clusterrole --no-headers -o custom-columns=":metadata.name" 2>/dev/null | \
        grep -E "prometheus|grafana|monitoring" || true)
    
    if [[ -n "${cluster_roles}" ]]; then
        while IFS= read -r role; do
            delete_resource_with_finalizers "clusterrole" "${role}"
        done <<< "${cluster_roles}"
    else
        log_info "No monitoring cluster roles found"
    fi
}

delete_cluster_role_bindings() {
    log_info "Deleting cluster role bindings"
    
    local cluster_bindings
    cluster_bindings=$(kubectl get clusterrolebinding --no-headers -o custom-columns=":metadata.name" 2>/dev/null | \
        grep -E "prometheus|grafana|monitoring" || true)
    
    if [[ -n "${cluster_bindings}" ]]; then
        while IFS= read -r binding; do
            delete_resource_with_finalizers "clusterrolebinding" "${binding}"
        done <<< "${cluster_bindings}"
    else
        log_info "No monitoring cluster role bindings found"
    fi
}

delete_namespaced_rbac() {
    log_info "Deleting namespaced RBAC resources"
    
    local namespaces
    namespaces=$(kubectl get namespaces --no-headers -o custom-columns=":metadata.name" 2>/dev/null || true)
    
    if [[ -z "${namespaces}" ]]; then
        log_warning "Could not retrieve namespaces list"
        return
    fi
    
    while IFS= read -r ns; do
        # Пропускаем системные namespace которые могут не существовать или быть в состоянии удаления
        if [[ "${ns}" == "kube-system" || "${ns}" == "kube-public" || "${ns}" == "kube-node-lease" ]]; then
            continue
        fi
        
        if ! namespace_exists "${ns}"; then
            log_debug "Namespace ${ns} does not exist, skipping"
            continue
        fi
        
        log_info "Processing namespace: ${ns}"
        
        # Delete roles
        delete_resources_by_type_and_pattern "role" "${ns}" "prometheus|grafana|monitoring"
        
        # Delete role bindings
        delete_resources_by_type_and_pattern "rolebinding" "${ns}" "prometheus|grafana|monitoring"
        
        # Delete service accounts
        delete_resources_by_type_and_pattern "serviceaccount" "${ns}" "prometheus|grafana|monitoring"
        
    done <<< "${namespaces}"
}

delete_namespaced_resources_bulk() {
    log_info "Step 3: Deleting namespaced resources"
    
    local namespaces
    namespaces=$(kubectl get namespaces --no-headers -o custom-columns=":metadata.name" 2>/dev/null || true)
    
    if [[ -z "${namespaces}" ]]; then
        log_warning "Could not retrieve namespaces list"
        return
    fi
    
    while IFS= read -r ns; do
        # Пропускаем системные namespace
        if [[ "${ns}" == "kube-system" || "${ns}" == "kube-public" || "${ns}" == "kube-node-lease" ]]; then
            continue
        fi
        
        if ! namespace_exists "${ns}"; then
            log_debug "Namespace ${ns} does not exist, skipping"
            continue
        fi
        
        log_info "Cleaning up monitoring resources in namespace: ${ns}"
        
        # Delete deployments, statefulsets, daemonsets
        for resource in deployment statefulset daemonset; do
            delete_resources_by_type_and_pattern "${resource}" "${ns}" "prometheus|grafana|monitoring"
        done
        
        # Delete services
        delete_resources_by_type_and_pattern "service" "${ns}" "prometheus|grafana|monitoring"
        
        # Delete configmaps and secrets with labels
        if [[ "${DRY_RUN}" != "true" ]]; then
            # For bulk resources, remove finalizers first if enabled
            if [[ "${REMOVE_FINALIZERS}" == "true" ]]; then
                remove_finalizers_bulk "configmap" "${ns}" "prometheus|grafana|monitoring"
                remove_finalizers_bulk "secret" "${ns}" "prometheus|grafana|monitoring"
            fi
            
            if kubectl -n "${ns}" delete configmap,secret \
                -l 'app.kubernetes.io/name in (prometheus, grafana)' \
                --ignore-not-found=true; then
                log_success "Deleted labeled configmaps and secrets in ${ns}"
            else
                log_error "Failed to delete some configmaps or secrets in ${ns}"
                ERROR_OCCURRED=true
            fi
        else
            log_info "DRY RUN: Would delete labeled configmaps and secrets in ${ns}"
        fi
        
    done <<< "${namespaces}"
}

remove_finalizers_bulk() {
    local resource_type="$1"
    local namespace="$2"
    local pattern="$3"
    
    # Проверяем существование namespace
    if ! namespace_exists "${namespace}"; then
        log_debug "Namespace ${namespace} does not exist, skipping bulk finalizer removal"
        return 0
    fi
    
    local resources
    resources=$(kubectl -n "${namespace}" get "${resource_type}" --no-headers -o custom-columns=":metadata.name" 2>/dev/null | \
        grep -E "${pattern}" || true)
    
    if [[ -n "${resources}" ]]; then
        while IFS= read -r resource; do
            remove_finalizers "${resource_type}" "${resource}" "${namespace}"
        done <<< "${resources}"
    fi
}

delete_webhooks_and_apiservices() {
    log_info "Step 4: Deleting webhooks and API services"
    
    # Delete validating webhook configurations
    local validating_webhooks
    validating_webhooks=$(kubectl get validatingwebhookconfiguration --no-headers -o custom-columns=":metadata.name" 2>/dev/null | \
        grep -E "prometheus|grafana|monitoring" || true)
    
    if [[ -n "${validating_webhooks}" ]]; then
        while IFS= read -r webhook; do
            delete_resource_with_finalizers "validatingwebhookconfiguration" "${webhook}"
        done <<< "${validating_webhooks}"
    fi
    
    # Delete mutating webhook configurations
    local mutating_webhooks
    mutating_webhooks=$(kubectl get mutatingwebhookconfiguration --no-headers -o custom-columns=":metadata.name" 2>/dev/null | \
        grep -E "prometheus|grafana|monitoring" || true)
    
    if [[ -n "${mutating_webhooks}" ]]; then
        while IFS= read -r webhook; do
            delete_resource_with_finalizers "mutatingwebhookconfiguration" "${webhook}"
        done <<< "${mutating_webhooks}"
    fi
    
    # Delete API services
    local api_services
    api_services=$(kubectl get apiservice --no-headers -o custom-columns=":metadata.name" 2>/dev/null | \
        grep -E "prometheus|grafana|monitoring" || true)
    
    if [[ -n "${api_services}" ]]; then
        while IFS= read -r api; do
            delete_resource_with_finalizers "apiservice" "${api}"
        done <<< "${api_services}"
    fi
}

cleanup_monitoring_namespace() {
    log_info "Step 5: Cleaning up monitoring namespace"
    
    if namespace_exists "monitoring"; then
        log_info "Found monitoring namespace"
        
        if [[ "${DRY_RUN}" != "true" ]]; then
            # Remove finalizers from all resources in monitoring namespace first
            if [[ "${REMOVE_FINALIZERS}" == "true" ]]; then
                log_info "Removing finalizers from all resources in monitoring namespace"
                remove_finalizers_from_all_in_namespace "monitoring"
            fi
            
            # Delete all resources in monitoring namespace
            if kubectl delete all --all -n monitoring --ignore-not-found=true; then
                log_success "Deleted all resources in monitoring namespace"
            else
                log_error "Failed to delete some resources in monitoring namespace"
                ERROR_OCCURRED=true
            fi
            
            # Delete remaining configmaps, secrets, etc.
            if kubectl delete configmaps,secrets,roles,rolebindings,serviceaccounts -n monitoring \
                -l 'app.kubernetes.io/name in (prometheus, grafana)' --ignore-not-found=true; then
                log_success "Deleted remaining monitoring resources"
            else
                log_error "Failed to delete some remaining monitoring resources"
                ERROR_OCCURRED=true
            fi
        else
            log_info "DRY RUN: Would cleanup monitoring namespace"
        fi
    else
        log_info "Monitoring namespace not found"
    fi
}

remove_finalizers_from_all_in_namespace() {
    local namespace="$1"
    
    # Проверяем существование namespace
    if ! namespace_exists "${namespace}"; then
        log_debug "Namespace ${namespace} does not exist, skipping finalizer removal"
        return 0
    fi
    
    local resource_types=("deployments" "statefulsets" "daemonsets" "services" "configmaps" "secrets" "roles" "rolebindings" "serviceaccounts")
    
    for resource_type in "${resource_types[@]}"; do
        local resources
        resources=$(kubectl -n "${namespace}" get "${resource_type}" --no-headers -o custom-columns=":metadata.name" 2>/dev/null | \
            grep -E "prometheus|grafana|monitoring" || true)
        
        if [[ -n "${resources}" ]]; then
            while IFS= read -r resource; do
                # Convert plural to singular (e.g., deployments -> deployment)
                local singular_type="${resource_type%?}"
                remove_finalizers "${singular_type}" "${resource}" "${namespace}"
            done <<< "${resources}"
        fi
    done
}

delete_remaining_resources() {
    log_info "Step 6: Deleting remaining resources"
    
    # Final pass to catch any remaining resources
    local resource_types=("configmaps" "secrets" "services" "serviceaccounts" "roles" "rolebindings")
    
    for resource_type in "${resource_types[@]}"; do
        local resources
        resources=$(kubectl get "${resource_type}" --all-namespaces --no-headers -o custom-columns=":metadata.namespace,:metadata.name" 2>/dev/null | \
            grep -E "prometheus|grafana|monitoring" || true)
        
        if [[ -n "${resources}" ]]; then
            while IFS= read -r resource; do
                local ns=$(echo "${resource}" | awk '{print $1}')
                local name=$(echo "${resource}" | awk '{print $2}')
                
                # Convert plural to singular (e.g., configmaps -> configmap)
                local singular_type="${resource_type%?}"
                delete_resource_with_finalizers "${singular_type}" "${name}" "${ns}"
            done <<< "${resources}"
        fi
    done
}

list_resources_with_finalizers() {
    log_info "Searching for resources with finalizers..."
    
    local cluster_scoped=("crd" "clusterrole" "clusterrolebinding" "validatingwebhookconfiguration" "mutatingwebhookconfiguration" "apiservice")
    
    # Namespaced resources
    local namespaced_resources=("deployments" "statefulsets" "daemonsets" "services" "configmaps" "secrets" "roles" "rolebindings" "serviceaccounts")
    
    log_info "=== Cluster-scoped resources with finalizers ==="
    for resource in "${cluster_scoped[@]}"; do
        local items
        items=$(kubectl get "${resource}" --no-headers -o custom-columns=":metadata.name,:metadata.finalizers" 2>/dev/null | \
            grep -v "<none>" | grep -v "^$" || true)
        
        if [[ -n "${items}" ]]; then
            echo "Resource type: ${resource}"
            echo "${items}" | while read -r line; do
                echo "  - ${line}"
            done
            echo
        fi
    done
    
    log_info "=== Namespaced resources with finalizers ==="
    for resource in "${namespaced_resources[@]}"; do
        local items
        items=$(kubectl get "${resource}" --all-namespaces --no-headers -o custom-columns=":metadata.namespace,:metadata.name,:metadata.finalizers" 2>/dev/null | \
            grep -v "<none>" | grep -v "^$" || true)
        
        if [[ -n "${items}" ]]; then
            echo "Resource type: ${resource}"
            echo "${items}" | while read -r line; do
                echo "  - ${line}"
            done
            echo
        fi
    done
}

check_remaining_resources() {
    log_info "Checking for remaining monitoring resources"
    
    local patterns=("prometheus" "grafana" "monitoring")
    local found_resources=false
    
    for pattern in "${patterns[@]}"; do
        local resources
        resources=$(kubectl get all --all-namespaces --no-headers -o custom-columns=":metadata.namespace,:metadata.name" 2>/dev/null | \
            grep "${pattern}" || true)
        
        if [[ -n "${resources}" ]]; then
            found_resources=true
            log_warning "Found remaining resources with pattern '${pattern}':"
            echo "${resources}" | while read -r line; do
                log_warning "  ${line}"
            done
        fi
    done
    
    if [[ "${found_resources}" == "false" ]]; then
        log_success "No remaining monitoring resources found"
    else
        log_warning "Some monitoring resources still exist"
    fi
}

cleanup_and_exit() {
    local exit_code=${1:-0}
    
    log_info "Cleaning up..."
    
    # Remove lock file
    if [[ -f "${LOCKFILE}" ]]; then
        rm -f "${LOCKFILE}"
        log_debug "Removed lock file: ${LOCKFILE}"
    fi
    
    # Calculate execution time
    if [[ -n "${CLEANUP_START_TIME}" ]]; then
        local ${end_time}
        end_time=$(date +%s)
        local duration=$((end_time - CLEANUP_START_TIME))
        log_info "Execution time: ${duration} seconds"
    fi
    
    log_info "Cleanup completed"
    exit ${exit_code}
}

handle_error() {
    local line_number=$1
    log_error "Error occurred in ${SCRIPT_NAME} at line ${line_number}"
    ERROR_OCCURRED=true
    # Don't exit immediately, let the script continue and clean up properly
}

log() {
    local level="$1"
    local message="$2"
    local color="$3"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo -e "${color}${timestamp} [${level}] ${message}${NC}" | tee -a "${LOG_FILE}"
}

log_info() { log "INFO" "$1" "${BLUE}"; }
log_success() { log "SUCCESS" "$1" "${GREEN}"; }
log_warning() { log "WARN" "$1" "${YELLOW}"; }
log_error() { log "ERROR" "$1" "${RED}"; }
log_debug() { 
    if [[ "${DEBUG:-false}" == "true" ]]; then
        log "DEBUG" "$1" "${NC}"
    fi
}

show_usage() {
    cat << EOF
Kubernetes Monitoring Stack Cleanup Script

Usage: ${SCRIPT_NAME} <command> [options]

Commands:
  cleanup           Perform the cleanup (requires confirmation)
  dry-run           Show what would be deleted without actually deleting
  status            Check for remaining monitoring resources
  list-finalizers   List all resources with finalizers

Options:
  DRY_RUN=true            Enable dry-run mode
  FORCE=true              Skip confirmation prompt
  REMOVE_FINALIZERS=false Disable finalizer removal (not recommended)
  DEBUG=true              Enable debug output

Examples:
  ${SCRIPT_NAME} dry-run
  ${SCRIPT_NAME} cleanup
  ${SCRIPT_NAME} list-finalizers
  FORCE=true ${SCRIPT_NAME} cleanup
  REMOVE_FINALIZERS=false ${SCRIPT_NAME} cleanup

WARNING: This script will delete ALL Prometheus and Grafana resources from your cluster!
EOF
}

# Make sure we cleanup on exit
trap cleanup_and_exit EXIT

# Run main function with all arguments
main "$@"