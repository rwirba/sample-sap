{{- define "java-hello-world.name" -}}
{{- .Chart.Name -}}
{{- end -}}

{{- define "java-hello-world.fullname" -}}
{{- printf "%s-%s" .Release.Name (include "java-hello-world.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}