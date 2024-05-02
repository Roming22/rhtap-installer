{{ define "rhtap.developer-hub.configure" }}
{{if and (index .Values "developer-hub") (eq (index .Values "developer-hub" "enabled") true)}}
- name: configure-developer-hub
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

      echo -n "Installing utils: "
      dnf install -y diffutils > /dev/null 2>/dev/null
      echo "OK"

      YQ_VERSION="v4.40.5"
      curl --fail --location --output "/usr/bin/yq" --silent --show-error "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64"
      chmod +x "/usr/bin/yq"

      CHART="{{ index .Values "trusted-application-pipeline" "name" }}"
      NAMESPACE="{{ .Release.Namespace }}"

      echo -n "* Generating 'app-config.extra.yaml': "
      APPCONFIGEXTRA="app-config.extra.yaml"
      touch "$APPCONFIGEXTRA"
      echo -n "."
      cat << EOF >> "$APPCONFIGEXTRA"
{{ include "rhtap.developer-hub.configure.app-config-extra" . | indent 6 }}
      EOF
      echo -n "."

      # Tekton integration
      while [ "$(kubectl get secret "$CHART-pipelines-secret" --ignore-not-found -o name | wc -l)" != "1" ]; do
        echo -ne "_"
        sleep 2
      done
      PIPELINES_PAC_URL="$(kubectl get secret "$CHART-pipelines-secret" -o yaml | yq '.data.webhook-url | @base64d')"
      yq -i ".integrations.github[0].apps[0].webhookUrl = \"$PIPELINES_PAC_URL\"" "$APPCONFIGEXTRA"
      echo "OK"

      kubectl create configmap redhat-developer-hub-app-config-extra \
        --from-file=app-config.extra.yaml="$APPCONFIGEXTRA" \
        -o yaml \
        --dry-run=client | kubectl apply -f - >/dev/null
      echo "OK"

      echo -n "* Generating redhat-developer-hub-{{index .Values "trusted-application-pipeline" "name"}}-config secret: "
      cat <<EOF | kubectl apply -f - >/dev/null
{{ include "rhtap.developer-hub.configure.extra_env" . | indent 6 }}
      EOF
      echo "OK"

      CRD="backstages"
      echo -n "* Waiting for '$CRD' CRD: "
      while [ $(kubectl api-resources | grep -c "^$CRD ") = "0" ] ; do
        echo -n "."
        sleep 3
      done
      echo "OK"

      echo -n "* Creating Backstage instance for RHTAP: "
      cat <<EOF | kubectl apply -f - >/dev/null
{{ include "rhtap.include.backstage" . | indent 6 }}
      EOF
      echo "OK"

      echo -n "* Waiting for route: "
      HOSTNAME=""
      while [ -z "$HOSTNAME" ]; do
        HOSTNAME="$(kubectl get routes "backstage-developer-hub" -o jsonpath="{.spec.host}" 2>/dev/null || echo "FAIL")"
        case "$HOSTNAME" in
          "FAIL")
            echo -n "_"
            sleep 3
            ;;
          *) ;;
        esac
      done
      echo -n "."
      if [ "$(kubectl get secret "$CHART-developer-hub-secret" -o name --ignore-not-found | wc -l)" = "0" ]; then
        kubectl create secret generic "$CHART-developer-hub-secret" \
          --from-literal="hostname=$HOSTNAME" >/dev/null
      fi
      echo "OK"

      # Wait for the UI to fully boot once before modifying the configuration.
      # This should avoid issues with DB migrations being interrupted and generating locks.
      # Once RHIDP-1691 is solved that safeguard could be removed.
      echo -n "* Waiting for UI: "
      until curl --fail --insecure --location --output /dev/null --silent "https://$HOSTNAME"; do
        echo -n "_"
        sleep 3
      done
      echo "OK"

      echo
      echo "Configuration successful"
{{ end }}
{{ end }}