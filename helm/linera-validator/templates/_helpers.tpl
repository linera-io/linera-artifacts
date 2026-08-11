{{/*
Expand the name of the chart.
*/}}
{{- define "linera-validator.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this
(by the DNS naming spec).
*/}}
{{/*
Component name prefix. Default (useComponentPrefix=false) = clean names
(proxy, shards, proxy-internal) matching what linera-network-init mints.
useComponentPrefix=true prefixes `<fullname>-` for legacy deployments whose
minted server config references validator-proxy/validator-shards — the
minted internal gRPC hostnames must always match these resource names.
*/}}
{{- define "linera-validator.componentPrefix" -}}
{{- if .Values.useComponentPrefix -}}
{{- printf "%s-" (include "linera-validator.fullname" .) -}}
{{- end -}}
{{- end }}

{{- define "linera-validator.fullname" -}}
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

{{/*
Chart label string (e.g. linera-validator-0.1.0).
*/}}
{{- define "linera-validator.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels applied to every resource.
*/}}
{{- define "linera-validator.labels" -}}
helm.sh/chart: {{ include "linera-validator.chart" . }}
{{ include "linera-validator.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Selector labels (used in spec.selector.matchLabels).
*/}}
{{- define "linera-validator.selectorLabels" -}}
app.kubernetes.io/name: {{ include "linera-validator.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Component-specific labels. Usage:
  {{ include "linera-validator.componentLabels" (dict "context" . "component" "shards") }}
*/}}
{{- define "linera-validator.componentLabels" -}}
{{ include "linera-validator.labels" .context }}
app.kubernetes.io/component: {{ .component }}
{{- end }}

{{/*
Component selector labels.
*/}}
{{- define "linera-validator.componentSelectorLabels" -}}
{{ include "linera-validator.selectorLabels" .context }}
app.kubernetes.io/component: {{ .component }}
{{- end }}

{{/*
ServiceAccount name to use.
*/}}
{{- define "linera-validator.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "linera-validator.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Image reference. `image.digest` (sha256:...) pins content-addressed and takes
precedence over `image.tag` — a digest reference can never move, unlike tags.
*/}}
{{- define "linera-validator.validatorImage" -}}
{{- $repo := required "validatorImage.repository is required (linera-server + linera-proxy)" .Values.validatorImage.repository -}}
{{- if .Values.validatorImage.digest -}}
{{- printf "%s@%s" $repo .Values.validatorImage.digest -}}
{{- else -}}
{{- $tag := .Values.validatorImage.tag | default .Chart.AppVersion -}}
{{- printf "%s:%s" $repo $tag -}}
{{- end -}}
{{- end }}

{{/*
Image for the containers that run the `linera` CLI rather than the server or
proxy — the storage-wait / storage-init init containers.

Upstream split the single image in two: linera-validator carries linera-server
and linera-proxy, linera-client carries `linera`. The validator image has no
`linera` binary at all, so pointing these init containers at it makes every
proxy and shard fail to start — they gate startup.

Falls back to `image` only when `clientImage.repository` is unset, so charts
pinned to a pre-split combined image keep working; set clientImage to use the
split images.
*/}}
{{- define "linera-validator.clientImage" -}}
{{- if .Values.clientImage.repository -}}
{{- if .Values.clientImage.digest -}}
{{- printf "%s@%s" .Values.clientImage.repository .Values.clientImage.digest -}}
{{- else -}}
{{- $tag := .Values.clientImage.tag | default .Values.validatorImage.tag | default .Chart.AppVersion -}}
{{- printf "%s:%s" .Values.clientImage.repository $tag -}}
{{- end -}}
{{- else -}}
{{- include "linera-validator.validatorImage" . -}}
{{- end -}}
{{- end }}

{{/*
Render CLI flags from a map. Keys are camelCase and converted to
--kebab-case. Null values are skipped. Each flag is emitted on its
own line followed by ` \` so the result can be embedded directly in
a shell command that continues on the next line.

Numeric values are formatted with %d to avoid Go's scientific
notation (1e+09) which the linera CLI does not accept.

Usage:
  command:
    - sh
    - -c
    - |
      exec /linera-server run \
        --storage ... \
        {{- include "linera-validator.cliFlags" .Values.shards.cli | nindent 8 }}
*/}}
{{- define "linera-validator.cliFlags" -}}
{{- $items := list -}}
{{- range $key, $value := . -}}
{{- if and (ne $key "extraArgs") (not (kindIs "invalid" $value)) -}}
{{- $rendered := $value -}}
{{- if or (kindIs "int" $value) (kindIs "int64" $value) (kindIs "float64" $value) -}}
{{- $rendered = printf "%d" (int64 $value) -}}
{{- end -}}
{{- $items = append $items (printf "--%s %v" ($key | kebabcase) $rendered) -}}
{{- end -}}
{{- end -}}
{{- with .extraArgs -}}
{{- range . -}}
{{- $items = append $items . -}}
{{- end -}}
{{- end -}}
{{- $items | join " \\\n" -}}
{{- end }}

{{/*
Name of the Secret holding genesis + server config. Either user-supplied
(.Values.validator.existingSecret) or generated by this chart.
*/}}
{{- define "linera-validator.configSecretName" -}}
{{- if .Values.validator.existingSecret -}}
{{- .Values.validator.existingSecret -}}
{{- else -}}
{{- printf "%s-config" (include "linera-validator.fullname" .) -}}
{{- end -}}
{{- end }}
