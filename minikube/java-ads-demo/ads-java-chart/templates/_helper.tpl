{{- define "ads-java-demo.name" -}}
{{- .Chart.Name -}}
{{- end -}}

{{- define "ads-java-demo.fullname" -}}
{{- printf "%s-%s" .Release.Name (include "ads-java-demo.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}