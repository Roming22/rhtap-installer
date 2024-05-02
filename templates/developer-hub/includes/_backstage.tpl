{{ define "rhtap.include.backstage" }}
---
apiVersion: rhdh.redhat.com/v1alpha1
kind: Backstage
metadata:
  name: developer-hub
  namespace: {{.Release.Namespace}}
spec:
  application:
    appConfig:
      mountPath: /opt/app-root/src
    extraFiles:
      mountPath: /opt/app-root/src
    replicas: 1
    route:
      enabled: true
  database:
    enableLocalDb: true
{{end}}