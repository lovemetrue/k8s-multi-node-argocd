{{/* vim: set filetype=mustache: */}}
{{/*
Expand the name of the chart.
*/}}
{{- define "settings.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "settings.fullname" -}}

{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "settings.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}


{{/*
Common labels
*/}}
{{- define "settings.labels" -}}
helm.sh/chart: {{ include "settings.chart" . }}
{{- range $k,$v := .Values.global.labels }}
{{ $k }}: {{ $v | quote }}
{{- end }}
{{ include "settings.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "settings.selectorLabels" -}}
app: {{ include "settings.name" . }}
tier: elma365
app.kubernetes.io/name: {{ include "settings.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/* Генератор списка hosts для ingress */}}
{{- define "generateHosts" -}}
  {{- $hosts := list }}
  {{- $servicesRequiringWildcardOnly := list "fileprotection" "front" "main" "notifier" "web-forms" }}

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
      {{- if not (has $.Chart.Name $servicesRequiringWildcardOnly) }}
        {{- if not (has $.Values.global.host $hosts) }}
          {{- $hosts = append $hosts $.Values.global.host }}
        {{- end }}
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
Сбор флагов для разных редакций
*/}}
{{- define "settings.featureFlags" -}}
  {{- $flags := list -}}

  {{- if eq .Values.global.solution "onPremise" -}}
    {{- if .Values.appconfig.onPremiseEnabledFeatureFlags -}}
      {{- $flags = concat $flags (.Values.appconfig.onPremiseEnabledFeatureFlags | default list) -}}
    {{- end -}}
    {{- if .Values.appconfig.onPremiseCustomEnabledFeatureFlags -}}
      {{- $flags = concat $flags (.Values.appconfig.onPremiseCustomEnabledFeatureFlags | default list) -}}
    {{- end -}}
  {{- else -}}
    {{- if .Values.appconfig.saasEnabledFeatureFlags -}}
      {{- $flags = concat $flags (.Values.appconfig.saasEnabledFeatureFlags | default list) -}}
    {{- end -}}
  {{- end -}}

  {{- if .Values.global.hubEnabled -}}
    {{- $flags = append $flags "allowServicehub" -}}
  {{- end -}}

  {{- if $flags -}}
    {{- join "," $flags -}}
  {{- else -}}
    {{- "" -}}
  {{- end -}}
{{- end -}}

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
{{ include "settings.supportsIngressClassname" . }}
*/}}
{{- define "settings.supportsIngressClassname" -}}
{{- if semverCompare "<1.18-0" (include "kubeVersion" .) -}}
{{- print "false" -}}
{{- else -}}
{{- print "true" -}}
{{- end -}}
{{- end -}}
