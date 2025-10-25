{{- define "mysql-db.name" -}}
{{- .Chart.Name -}}
{{- end -}}

{{- define "mysql-db.fullname" -}}
{{- printf "%s-%s" .Release.Name (include "mysql-db.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
