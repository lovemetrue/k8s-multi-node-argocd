{{/*
Expand the name of the chart.
*/}}
{{- define "linkhub.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "linkhub.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Common labels
*/}}
{{- define "linkhub.labels" -}}
helm.sh/chart: {{ include "linkhub.chart" . }}
{{- range $k,$v := .Values.global.labels }}
{{ $k }}: {{ $v | quote }}
{{- end }}
{{ include "linkhub.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "linkhub.selectorLabels" -}}
app: {{ include "linkhub.name" . }}
tier: elma365
app.kubernetes.io/name: {{ include "linkhub.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "linkhub.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
    {{ default (include "linkhub.fullname" .) .Values.serviceAccount.name }}
{{- else -}}
    {{ default "default" .Values.serviceAccount.name }}
{{- end -}}
{{- end -}}

{{/*
Create rabbitmq user basen on namespace
*/}}
{{- define "linkhub.rmquser" -}}
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
  {{- else if eq $.Values.global.solution "hub" }}
    {{- if and (hasKey $.Values.global "hub") $.Values.global.hub (gt (len $.Values.global.hub) 0) }}
      {{- range $company := $.Values.global.hub }}
        {{- if hasKey $company "name" }}
          {{- $host := printf "%s.%s" $company.name $.Values.global.host }}
          {{- if not (has $host $hosts) }}
            {{- $hosts = append $hosts $host }}
          {{- end }}
        {{- end }}
      {{- end }}
    {{- else }}
      {{- $wildcardHost := printf "*.%s" $.Values.global.host }}
      {{- if not (has $wildcardHost $hosts) }}
        {{- $hosts = append $hosts $wildcardHost }}
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
{{ include "linkhub.supportsIngressClassname" . }}
*/}}
{{- define "linkhub.supportsIngressClassname" -}}
{{- if semverCompare "<1.18-0" (include "kubeVersion" .) -}}
{{- print "false" -}}
{{- else -}}
{{- print "true" -}}
{{- end -}}
{{- end -}}

{{/* Generate connection JSON config */}}
{{- define "linkhub.connection.json" -}}
{"url":{{ .url | quote }},{{- if eq .type "cluster" }}"clusterId":{{ .id | quote }},{{- else if eq .type "tenant" }}"tenantId":{{ .id | quote }},{{- end }}"type":{{ default "HttpNoAuth" .authType | quote }},"providerData":{{ .providerData | default dict | toJson }}}
{{- end }}
