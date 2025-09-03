# Prometheus Exporters

Prometheus exporter for postgres, mongodb, minio, rabbitmq, redis

## Prerequisites

- Kubernetes 1.16+
- Helm 3+

## Add Helm Chart Repository

```console
helm repo add elma365 https://charts.elma365.tech
helm repo update
```

## Generate a configuration token for use minio metrics with Prometheus.

```console
mc alias set my_alias http://minio.local accessKey secretKey
mc admin prometheus generate my_alias
```

## Configure values

## Install Chart

```console
helm show values elma365/dbsexporter > values-dbsexporter.yaml
helm upgrade --install -n namespace dbsexporter elma365/dbsexporter -f values-dbsexporter.yaml
```

## Uninstall Chart

```console
helm uninstall [RELEASE_NAME]
```

## Configuration

The following table lists the configurable parameters of the Dbsexporter chart and their default values.

| Parameter                | Description             | Default        |
| ------------------------ | ----------------------- | -------------- |
| `dbsexporter.grafana-dashboards.dashboards.enabled` |  | `true` |
| `dbsexporter.grafana-dashboards.dashboards.grafanaFolder` |  | `"dbs"` |
| `dbsexporter.prometheus-minio-exporter.instances` |  | `[{"name": "minio-job", "token": "generated_token", "path": "/minio/v2/metrics/cluster", "host": "minio.local", "port": 80, "interval": "30s", "scheme": "http"}]` |
| `dbsexporter.prometheus-mongodb-exporter.instances` |  | `[{"name": "mongodb", "uri": "mongodb://mongodb:27017"}]` |
| `dbsexporter.prometheus-mongodb-exporter.serviceMonitor.interval` |  | `"300s"` |
| `dbsexporter.prometheus-mongodb-exporter.serviceMonitor.scrapeTimeout` |  | `"120s"` |
| `dbsexporter.prometheus-mongodb-exporter.serviceMonitor.metricRelabelings` |  | `[{"sourceLabels": ["__name__"], "action": "drop", "regex": "(mongodb_top_.+)"}]` |
| `dbsexporter.prometheus-postgres-exporter.config.instances` |  | `[{"name": "postgres", "host": "example.ru", "user": "postgres", "userSecret": {}, "password": "postgres_password", "passwordFile": "", "passwordSecret": {}, "pgpassfile": "", "port": "5432", "database": "", "sslmode": "disable", "extraParams": ""}]` |
| `dbsexporter.prometheus-postgres-exporter.serviceMonitor.interval` |  | `"300s"` |
| `dbsexporter.prometheus-postgres-exporter.serviceMonitor.scrapeTimeout` |  | `"120s"` |
| `dbsexporter.prometheus-postgres-exporter.serviceMonitor.sampleLimit` |  | `0` |
| `dbsexporter.prometheus-postgres-exporter.serviceMonitor.timeout` |  | `"90s"` |
| `dbsexporter.prometheus-postgres-exporter.serviceMonitor.metricRelabelings` |  | `[{"sourceLabels": ["__name__"], "action": "drop", "regex": "(pg_stat_user_.+|pg_statio_.+)"}]` |
| `dbsexporter.prometheus-rabbitmq-exporter.rabbitmq.instances` |  | `[{"name": "rabbitmq", "url": "http://rabbitmq:15672", "user": "rabbitmq_user", "password": "rabbitmq_password", "existingPasswordSecret": "rabbitmq-secret", "existingPasswordSecretKey": "password", "capabilities": "bert,no_sort", "include_queues": ".*", "include_vhost": ".*", "skip_queues": "^$", "skip_verify": "false", "skip_vhost": "^$", "exporters": "exchange,node,overview,queue", "output_format": "TTY", "timeout": 60, "max_queues": 0, "excludeMetrics": "", "configMapOverrideReference": ""}]` |
| `dbsexporter.prometheus-rabbitmq-exporter.prometheus.monitor.enabled` |  | `true` |
| `dbsexporter.prometheus-rabbitmq-exporter.prometheus.monitor.additionalLabels.cluster` |  | `null` |
| `dbsexporter.prometheus-rabbitmq-exporter.prometheus.monitor.interval` |  | `"60s"` |
| `dbsexporter.prometheus-rabbitmq-exporter.prometheus.monitor.timeout` |  | `"30s"` |
| `dbsexporter.prometheus-rabbitmq-exporter.prometheus.monitor.namespace` |  | `[]` |
| `dbsexporter.prometheus-rabbitmq-exporter.prometheus.monitor.metricRelabelings` |  | `[]` |
| `dbsexporter.prometheus-rabbitmq-exporter.prometheus.monitor.relabelings` |  | `[]` |
| `dbsexporter.prometheus-rabbitmq-exporter.prometheus.rules.enabled` |  | `false` |
| `dbsexporter.prometheus-rabbitmq-exporter.prometheus.rules.additionalLabels` |  | `{}` |
| `dbsexporter.prometheus-rabbitmq-exporter.prometheus.rules.namespace` |  | `""` |
| `dbsexporter.prometheus-rabbitmq-exporter.prometheus.rules.additionalRules` |  | `null` |
| `dbsexporter.prometheus-redis-exporter.instances` |  | `[{"name": "redis1", "redisAddress": "redis://redis:6379/0"}]` |
