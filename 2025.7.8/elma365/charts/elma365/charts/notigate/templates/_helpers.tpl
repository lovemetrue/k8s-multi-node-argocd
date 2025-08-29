{{/*
Expand the name of the chart.
*/}}
{{- define "notigate.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "notigate.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Common labels
*/}}
{{- define "notigate.labels" -}}
helm.sh/chart: {{ include "notigate.chart" . }}
{{- range $k,$v := .Values.global.labels }}
{{ $k }}: {{ $v | quote }}
{{- end }}
{{ include "notigate.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "notigate.selectorLabels" -}}
app: {{ include "notigate.name" . }}
tier: elma365
app.kubernetes.io/name: {{ include "notigate.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "notigate.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
    {{ default (include "notigate.fullname" .) .Values.serviceAccount.name }}
{{- else -}}
    {{ default "default" .Values.serviceAccount.name }}
{{- end -}}
{{- end -}}

{{/*
Create rabbitmq user basen on namespace
*/}}
{{- define "notigate.rmquser" -}}
{{- printf "%s-%s" .Release.Namespace .Chart.Name | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Генератор списка hosts для ingress */}}
{{- define "generateHosts" -}}
  {{- $hosts := list }}
  {{- if eq $.Values.global.solution "saas" }}
    {{- $hasNonWildcardCompanies := false }}
    {{- if and (hasKey $.Values.global "companies") $.Values.global.companies (ne (len $.Values.global.companies) 0) }}
      {{- range $company := $.Values.global.companies }}
        {{- if ne $company "*" }}
          {{- $hasNonWildcardCompanies = true }}
          {{- $host := printf "%s.%s" $company $.Values.global.host }}
          {{- if not (has $host $hosts) }}
            {{- $hosts = append $hosts $host }}
          {{- end }}
        {{- end }}
      {{- end }}
    {{- end }}
    {{- if not $hasNonWildcardCompanies }}
      {{- $wildcardHost := printf "*.%s" $.Values.global.host }}
      {{- if not (has $wildcardHost $hosts) }}
        {{- $hosts = append $hosts $wildcardHost }}
      {{- end }}
    {{- end }}
  {{- else if and (eq $.Values.global.solution "onPremise") (eq $.Values.global.edition "hub") }}
    {{- range $company := $.Values.global.hub }}
      {{- $host := printf "%s.%s" $company.name $.Values.global.host }}
      {{- if not (has $host $hosts) }}
        {{- $hosts = append $hosts $host }}
      {{- end }}
    {{- end }}
  {{- else }}
    {{- if not (has $.Values.global.host $hosts) }}
      {{- $hosts = append $hosts $.Values.global.host }}
    {{- end }}
  {{- end }}
  {{- if and (hasKey $.Values.global "multicluster") (hasKey $.Values.global.multicluster "enabled") $.Values.global.multicluster.enabled }}
    {{- if and (hasKey $.Values.global.multicluster "clusterHost") $.Values.global.multicluster.clusterHost }}
      {{- $clusterHost := $.Values.global.multicluster.clusterHost }}
      {{- if not (has $clusterHost $hosts) }}
        {{- $hosts = append $hosts $clusterHost }}
      {{- end }}
    {{- end }}
  {{- end }}
  {{- toJson $hosts -}}
{{- end }}

{{/*
Return the target Kubernetes version
*/}}
{{- define "kubeVersion" -}}
{{- if .Values.global }}
    {{- if .Values.global.kubeVersion }}
    {{- .Values.global.kubeVersion -}}
    {{- else }}
    {{- default .Capabilities.KubeVersion.Version .Values.kubeVersion -}}
    {{- end -}}
{{- else }}
{{- default .Capabilities.KubeVersion.Version .Values.kubeVersion -}}
{{- end -}}
{{- end -}}

{{/*
Returns true if the ingressClassname field is supported
Usage:
{{ include "notigate.supportsIngressClassname" . }}
*/}}
{{- define "notigate.supportsIngressClassname" -}}
{{- if semverCompare "<1.18-0" (include "kubeVersion" .) -}}
{{- print "false" -}}
{{- else -}}
{{- print "true" -}}
{{- end -}}
{{- end -}}
