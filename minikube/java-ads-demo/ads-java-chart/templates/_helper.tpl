{{- define "ads-java-chart.name" -}}
ads-java-demo
{{- end -}}

{{- define "ads-java-chart.fullname" -}}
{{- printf "%s-%s" .Release.Name (include "ads-java-chart.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}