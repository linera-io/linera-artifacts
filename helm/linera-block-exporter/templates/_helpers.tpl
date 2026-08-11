{{/*
Expand the name of the chart.
*/}}
{{- define "linera-block-exporter.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Fully qualified name.
*/}}
{{- define "linera-block-exporter.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{- define "linera-block-exporter.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels.
*/}}
{{- define "linera-block-exporter.labels" -}}
helm.sh/chart: {{ include "linera-block-exporter.chart" . }}
{{ include "linera-block-exporter.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/component: exporter
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{- define "linera-block-exporter.selectorLabels" -}}
app.kubernetes.io/name: {{ include "linera-block-exporter.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
ServiceAccount name.
*/}}
{{- define "linera-block-exporter.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "linera-block-exporter.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Image reference.
*/}}
{{- define "linera-block-exporter.exporterImage" -}}
{{- $tag := .Values.exporterImage.tag | default .Chart.AppVersion -}}
{{- printf "%s:%s" .Values.exporterImage.repository $tag -}}
{{- end }}

{{/*
Image for the storage-check init container, which runs the `linera` CLI.
Falls back to `image` when clientImage.repository is unset.
*/}}
{{- define "linera-block-exporter.clientImage" -}}
{{- if .Values.clientImage.repository -}}
{{- if .Values.clientImage.digest -}}
{{- printf "%s@%s" .Values.clientImage.repository .Values.clientImage.digest -}}
{{- else -}}
{{- $tag := .Values.clientImage.tag | default .Values.exporterImage.tag | default .Chart.AppVersion -}}
{{- printf "%s:%s" .Values.clientImage.repository $tag -}}
{{- end -}}
{{- else -}}
{{- include "linera-block-exporter.exporterImage" . -}}
{{- end -}}
{{- end }}

{{/*
ConfigMap name (one ConfigMap with N TOML files, one per replica).
*/}}
{{- define "linera-block-exporter.configMapName" -}}
{{- printf "%s-config" (include "linera-block-exporter.fullname" .) -}}
{{- end }}
