#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="monitoring"

echo "🚀 Начинаем чистку Tempo и Pyroscope из namespace: ${NAMESPACE}"
echo "----------------------------------------------"

# Функция для безопасного удаления
safe_delete() {
    kubectl delete "$@" --ignore-not-found --timeout=60s || true
}

# 1. Удаляем все ресурсы Tempo
echo "🧹 Удаляем ресурсы Tempo..."
safe_delete all -n "$NAMESPACE" -l app.kubernetes.io/name=tempo
safe_delete statefulset -n "$NAMESPACE" -l app.kubernetes.io/name=tempo
safe_delete daemonset -n "$NAMESPACE" -l app.kubernetes.io/name=tempo
safe_delete configmap -n "$NAMESPACE" -l app.kubernetes.io/name=tempo
safe_delete secret -n "$NAMESPACE" -l app.kubernetes.io/name=tempo
safe_delete pvc -n "$NAMESPACE" -l app.kubernetes.io/name=tempo
safe_delete sa -n "$NAMESPACE" -l app.kubernetes.io/name=tempo
safe_delete role,rolebinding -n "$NAMESPACE" -l app.kubernetes.io/name=tempo

# Удаляем ресурсы Loki.
safe_delete all -n "$NAMESPACE" -l app.kubernetes.io/name=loki
safe_delete statefulset -n "$NAMESPACE" -l app.kubernetes.io/name=loki
safe_delete daemonset -n "$NAMESPACE" -l app.kubernetes.io/name=loki
safe_delete configmap -n "$NAMESPACE" -l app.kubernetes.io/name=loki
safe_delete secret -n "$NAMESPACE" -l app.kubernetes.io/name=loki
safe_delete pvc -n "$NAMESPACE" -l app.kubernetes.io/name=loki
safe_delete sa -n "$NAMESPACE" -l app.kubernetes.io/name=loki
safe_delete role,rolebinding -n "$NAMESPACE" -l app.kubernetes.io/name=loki     
# 2. Удаляем CRD Tempo
echo "🧹 Удаляем CRD Tempo..."
kubectl get crd | grep tempo | awk '{print $1}' | xargs -r kubectl delete crd --ignore-not-found || true

# 3. Удаляем все ресурсы Pyroscope
echo "🧹 Удаляем ресурсы Pyroscope..."
safe_delete all -n "$NAMESPACE" -l app.kubernetes.io/name=pyroscope
safe_delete statefulset -n "$NAMESPACE" -l app.kubernetes.io/name=pyroscope
safe_delete daemonset -n "$NAMESPACE" -l app.kubernetes.io/name=pyroscope
safe_delete configmap -n "$NAMESPACE" -l app.kubernetes.io/name=pyroscope
safe_delete secret -n "$NAMESPACE" -l app.kubernetes.io/name=pyroscope
safe_delete pvc -n "$NAMESPACE" -l app.kubernetes.io/name=pyroscope
safe_delete sa -n "$NAMESPACE" -l app.kubernetes.io/name=pyroscope
safe_delete role,rolebinding -n "$NAMESPACE" -l app.kubernetes.io/name=pyroscope

# 4. Удаляем CRD Pyroscope
echo "🧹 Удаляем CRD Pyroscope..."
kubectl get crd | grep pyroscope | awk '{print $1}' | xargs -r kubectl delete crd --ignore-not-found || true

# 5. Удаляем все ресуры Grafana.
echo "🧹 Удаляем ресурсы Grafana..."
safe_delete all -n "$NAMESPACE" -l app.kubernetes.io/name=grafana
safe_delete statefulset -n "$NAMESPACE" -l app.kubernetes.io/name=grafana
safe_delete daemonset -n "$NAMESPACE" -l app.kubernetes.io/name=grafana
safe_delete configmap -n "$NAMESPACE" -l app.kubernetes.io/name=grafana
safe_delete secret -n "$NAMESPACE" -l app.kubernetes.io/name=grafana
safe_delete pvc -n "$NAMESPACE" -l app.kubernetes.io/name=grafana
safe_delete sa -n "$NAMESPACE" -l app.kubernetes.io/name=grafana
safe_delete role,rolebinding -n "$NAMESPACE" -l app.kubernetes.io/name=grafana
safe_delete crd -n "$NAMESPACE" -l app.kubernetes.io/name=grafana
safe_delete service -n "$NAMESPACE" -l app.kubernetes.io/name=grafana
safe_delete ingress -n "$NAMESPACE" -l app.kubernetes.io/name=grafana

# 4. Удаляем CRD Pyroscope
echo "🧹 Удаляем CRD Pyroscope..."
kubectl get crd | grep grafana | awk '{print $1}' | xargs -r kubectl delete crd --ignore-not-found || true

# 5. Проверка
echo "✅ Проверяем, что ничего не осталось..."
kubectl get all -n "$NAMESPACE" | grep -E 'tempo|pyroscope' || echo "🎯 Все ресурсы удалены."

echo "🏁 Очистка завершена."