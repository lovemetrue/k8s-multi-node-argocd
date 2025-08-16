#!/bin/bash
set -euo pipefail

# 1. Удаление CRD Prometheus Operator
echo "Deleting Prometheus CRDs..."
kubectl delete crd \
  alertmanagerconfigs.monitoring.coreos.com \
  alertmanagers.monitoring.coreos.com \
  podmonitors.monitoring.coreos.com \
  probes.monitoring.coreos.com \
  prometheusagents.monitoring.coreos.com \
  prometheuses.monitoring.coreos.com \
  prometheusrules.monitoring.coreos.com \
  scrapeconfigs.monitoring.coreos.com \
  servicemonitors.monitoring.coreos.com \
  thanosrulers.monitoring.coreos.com \
  --ignore-not-found=true

# 2. Удаление всех RBAC-ресурсов, связанных с Prometheus и Grafana
echo "Deleting RBAC resources..."

# Удаление кластерных ролей
kubectl get clusterrole -o jsonpath='{.items[?(@.metadata.name ~ "prometheus|grafana")].metadata.name}' | \
  xargs -r kubectl delete clusterrole --ignore-not-found=true

# Удаление кластерных привязок ролей
kubectl get clusterrolebinding -o jsonpath='{.items[?(@.metadata.name ~ "prometheus|grafana")].metadata.name}' | \
  xargs -r kubectl delete clusterrolebinding --ignore-not-found=true

# 3. Удаление ресурсов в неймспейсах
for ns in $(kubectl get ns -o name | cut -d/ -f2); do
  echo "Processing namespace: $ns"
  
  # Удаление ролей
  kubectl -n $ns get role -o jsonpath='{.items[?(@.metadata.name ~ "prometheus|grafana")].metadata.name}' | \
    xargs -r kubectl -n $ns delete role --ignore-not-found=true
  
  # Удаление привязок ролей
  kubectl -n $ns get rolebinding -o jsonpath='{.items[?(@.metadata.name ~ "prometheus|grafana")].metadata.name}' | \
    xargs -r kubectl -n $ns delete rolebinding --ignore-not-found=true
  
  # Удаление сервисных аккаунтов
  kubectl -n $ns get serviceaccount -o jsonpath='{.items[?(@.metadata.name ~ "prometheus|grafana")].metadata.name}' | \
    xargs -r kubectl -n $ns delete serviceaccount --ignore-not-found=true
done

# 4. Удаление остаточных ресурсов
echo "Deleting remaining resources..."

# Удаление admission webhooks
kubectl delete validatingwebhookconfiguration -l 'app.kubernetes.io/name in (prometheus, grafana)' --ignore-not-found=true
kubectl delete mutatingwebhookconfiguration -l 'app.kubernetes.io/name in (prometheus, grafana)' --ignore-not-found=true

# Удаление APIServices
kubectl delete apiservice -l 'app.kubernetes.io/name in (prometheus, grafana)' --ignore-not-found=true

# 5. Очистка неймспейса мониторинга (если существует)
if kubectl get ns monitoring >/dev/null 2>&1; then
  echo "Deleting all resources in monitoring namespace"
  kubectl delete all --all -n monitoring --ignore-not-found=true
  kubectl delete configmaps,secrets,roles,rolebindings,serviceaccounts -n monitoring \
    -l 'app.kubernetes.io/name in (prometheus, grafana)' --ignore-not-found=true
fi

echo "Cleanup completed successfully!"