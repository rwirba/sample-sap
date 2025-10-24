{{- define "java-ads-demo.name" -}}
{{- .Chart.Name -}}
{{- end -}}

{{- define "java-ads-demo.fullname" -}}
{{- printf "%s-%s" .Release.Name (include "java-ads-demo.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
