{{define "rhtap.developer-hub.test"}}
{{if and (index .Values "developer-hub") (eq (index .Values "developer-hub" "enabled") true)}}
- name: test-developer-hub
  image: "registry.redhat.io/openshift4/ose-tools-rhel8:latest"
  workingDir: /tmp
  command:
    - /bin/bash
    - -c
    - |
      set -o errexit
      set -o nounset
      set -o pipefail
    {{ if eq .Values.debug.script true }}
      set -x
    {{ end }}
      EXIT_CODE=0

      echo -n "* UI: "
      HOSTNAME="$(kubectl get routes "backstage-developer-hub" -o jsonpath="{.spec.host}")"
      if ! curl --fail --insecure --location --output /dev/null --silent "https://$HOSTNAME"; then
        echo "FAIL"
        EXIT_CODE=1
      else
        echo "OK"
      fi

      exit $EXIT_CODE
{{end}}
{{end}}