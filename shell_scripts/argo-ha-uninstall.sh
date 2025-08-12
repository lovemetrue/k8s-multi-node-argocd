#!/bin/bash
set -eo pipefail

# Функция для проверки выполнения команд
check() {
    if [ $? -eq 0 ]; then
        echo -e "\033[32m[SUCCESS]\033[0m $1"
    else
        echo -e "\033[31m[ERROR]\033[0m $2"
        exit 1
    fi
}

echo -e "\n\033[1m=== Полное удаление Argo CD HA ===\033[0m"

# 1. Удаление релиза Helm
echo -e "\n\033[1mУдаление релиза Helm...\033[0m"
if helm list -n argocd | grep -q "argocd"; then
    helm uninstall argocd -n argocd
    check "Helm-релиз argocd удален" "Ошибка удаления Helm-релиза"
else
    echo "Helm-релиз argocd не найден, пропускаем"
fi

# 2. Удаление по меткам
echo -e "\n\033[1mУдаление ресурсов по меткам...\033[0m"
labels=(
    "app.kubernetes.io/name=argocd"
    "app.kubernetes.io/part-of=argocd"
    "app.kubernetes.io/instance=argocd"
)

for label in "${labels[@]}"; do
    echo "Удаление ресурсов с меткой: $label"
    
    # Удаление основных ресурсов
    kubectl delete all,cm,secrets,sa,roles,rolebindings,pvc,ingresses,daemonsets,statefulsets,jobs,cronjobs -A -l "$label" --ignore-not-found
    check "Ресурсы с меткой $label удалены" "Ошибка удаления ресурсов"
    
    # Удаление кластерных ресурсов
    kubectl delete clusterroles,clusterrolebindings -l "$label" --ignore-not-found
    check "Кластерные ресурсы с меткой $label удалены" "Ошибка удаления кластерных ресурсов"
done

# 3. Удаление CRD
echo -e "\n\033[1mУдаление Custom Resource Definitions (CRD)...\033[0m"
crds=(
    applications.argoproj.io
    applicationsets.argoproj.io
    appprojects.argoproj.io
    argocds.argoproj.io
)

for crd in "${crds[@]}"; do
    kubectl delete crd $crd --ignore-not-found
    check "Удален CRD: $crd" "Ошибка удаления CRD"
done

# 4. Удаление namespace с очисткой финализаторов
echo -e "\n\033[1mУдаление namespace argocd...\033[0m"
if kubectl get ns argocd &> /dev/null; then
    # Проверка состояния namespace
    namespace_status=$(kubectl get ns argocd -o jsonpath='{.status.phase}')
    
    if [ "$namespace_status" == "Terminating" ]; then
        echo "Namespace argocd в состоянии Terminating, очищаем финализаторы..."
        kubectl get namespace argocd -o json | \
            jq 'del(.spec.finalizers[])' | \
            kubectl replace --raw "/api/v1/namespaces/argocd/finalize" -f -
    fi
    
    kubectl delete ns argocd --ignore-not-found
    check "Namespace argocd удален" "Ошибка удаления namespace"
else
    echo "Namespace argocd не найден, пропускаем"
fi

# 5. Удаление дополнительных компонентов Redis HA
echo -e "\n\033[1mУдаление Redis HA...\033[0m"
kubectl delete statefulset,svc -n argocd -l app.kubernetes.io/name=redis-ha --ignore-not-found
check "Компоненты Redis HA удалены" "Ошибка удаления Redis"

# 6. Очистка финальных зависимостей
echo -e "\n\033[1mОчистка финальных зависимостей...\033[0m"
kubectl delete validatingwebhookconfigurations -l app.kubernetes.io/part-of=argocd --ignore-not-found
kubectl delete mutatingwebhookconfigurations -l app.kubernetes.io/part-of=argocd --ignore-not-found
kubectl delete apiservices -l app.kubernetes.io/part-of=argocd --ignore-not-found

# 7. Проверка отсутствия ресурсов
echo -e "\n\033[1mПроверка результатов...\033[0m"
echo "Оставшиеся ресурсы Argo CD:"
kubectl get all,cm,secret,pv,pvc,crd,clusterroles,clusterrolebindings -A | grep -E 'argocd|argo' || \
    echo -e "\033[32mРесурсы Argo CD не обнаружены\033[0m"

echo -e "\n\033[1m=== Удаление Argo CD HA завершено ===\033[0m"