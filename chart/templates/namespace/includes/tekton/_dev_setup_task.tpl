{{ define "rhtap.namespace.dev_setup_task" }}
apiVersion: tekton.dev/v1
kind: Task
metadata:
  name: {{index .Values "trusted-application-pipeline" "name"}}-dev-namespace-setup
  annotations:
    helm.sh/chart: "{{.Chart.Name}}-{{.Chart.Version}}"
spec:
  description: >-
    Create the required resources for {{.Chart.Name}} tasks to run in a namespace.
  params:
    {{- $github_token := ""}}
    {{- if index .Values "openshift-gitops" "git-token"}}
    {{- $github_token = (index .Values "openshift-gitops" "git-token" | replace "$" "\\$")}}
    {{- end}}
    - default: {{$github_token}}
      description: |
        GitHub token
      name: github_token
      type: string
    {{$gitlab_token := ""}}
    {{if .Values.git.gitlab}}
    {{$gitlab_token = (.Values.git.gitlab.token)}}
    {{end}}
    - default: "{{$gitlab_token | replace "$" "\\$"}}"
      description: |
        GitLab Personal Access Token
      name: gitlab_token
      type: string
    - default: {{index .Values "quay" "dockerconfigjson" | replace "$" "\\$"}}
      description: |
        Image registry token
      name: quay_dockerconfigjson
      type: string
    - default: {{index .Values "acs" "central-endpoint" | replace "$" "\\$"}}
      description: |
        StackRox Central address:port tuple
        (example - rox.stackrox.io:443)
      name: acs_central_endpoint
      type: string
    - default: {{index .Values "acs" "api-token" | replace "$" "\\$"}}
      description: |
        StackRox API token with CI permissions
      name: acs_api_token
      type: string
  steps:
    - env:
      - name: GITHUB_TOKEN
        value: \$(params.github_token)
      - name: GITLAB_TOKEN
        value: \$(params.gitlab_token)
      - name: QUAY_DOCKERCONFIGJSON
        value: \$(params.quay_dockerconfigjson)
      - name: ROX_API_TOKEN
        value: \$(params.acs_api_token)
      - name: ROX_ENDPOINT
        value: \$(params.acs_central_endpoint)
      image: "registry.redhat.io/openshift4/ose-tools-rhel8:latest"
      name: setup
      script: |
        #!/usr/bin/env bash
        set -o errexit
        set -o nounset
        set -o pipefail
      {{if eq .Values.debug.script true}}
        set -x
      {{end}}

        SECRET_NAME="cosign-pub"
        if [ -n "$COSIGN_SIGNING_PUBLIC_KEY" ]; then
          echo -n "* \$SECRET_NAME secret: "
          cat <<EOF | kubectl apply -f - >/dev/null
        apiVersion: v1
        data:
          cosign.pub: $COSIGN_SIGNING_PUBLIC_KEY
        kind: Secret
        metadata:
          labels:
            app.kubernetes.io/instance: default
            app.kubernetes.io/part-of: tekton-chains
            helm.sh/chart: {{.Chart.Name}}-{{.Chart.Version}}
            operator.tekton.dev/operand-name: tektoncd-chains
          name: \$SECRET_NAME
        type: Opaque
        EOF
          echo "OK"
        fi

        SECRET_NAME="gitlab-auth-secret"
        if [ -n "\$GITLAB_TOKEN" ]; then
          echo -n "* \$SECRET_NAME secret: "
          kubectl create secret generic "\$SECRET_NAME" \
            --from-literal=password=\$GITLAB_TOKEN \
            --from-literal=username=oauth2 \
            --type=kubernetes.io/basic-auth \
            --dry-run=client -o yaml | kubectl apply --filename - --overwrite=true >/dev/null
          kubectl annotate secret "\$SECRET_NAME" "helm.sh/chart={{.Chart.Name}}-{{.Chart.Version}}" >/dev/null
          echo "OK"
        fi

        SECRET_NAME="gitops-auth-secret"
        if [ -n "\$GITHUB_TOKEN" ]; then
          echo -n "* \$SECRET_NAME secret: "
          kubectl create secret generic "\$SECRET_NAME" \
            --from-literal=password=\$GITHUB_TOKEN \
            --type=kubernetes.io/basic-auth \
            --dry-run=client -o yaml | kubectl apply --filename - --overwrite=true >/dev/null
          kubectl annotate secret "\$SECRET_NAME" "helm.sh/chart={{.Chart.Name}}-{{.Chart.Version}}" >/dev/null
          echo "OK"
        fi
        
        SECRET_NAME="rhtap-image-registry-token"
        if [ -n "\$QUAY_DOCKERCONFIGJSON" ]; then
          echo -n "* \$SECRET_NAME secret: "
          DATA=$(mktemp)
          echo -n "\$QUAY_DOCKERCONFIGJSON" >"\$DATA"
          kubectl create secret docker-registry "\$SECRET_NAME" \
            --from-file=.dockerconfigjson="\$DATA" --dry-run=client -o yaml | \
            kubectl apply --filename - --overwrite=true >/dev/null
          rm "\$DATA"
          echo -n "."
          kubectl annotate secret "\$SECRET_NAME" "helm.sh/chart={{.Chart.Name}}-{{.Chart.Version}}" >/dev/null
          echo -n "."
          while ! kubectl get serviceaccount pipeline >/dev/null &>2; do
            sleep 2
            echo -n "_"
          done
          for SA in default pipeline; do
            kubectl patch serviceaccounts "\$SA" --patch "
          secrets:
            - name: \$SECRET_NAME
          imagePullSecrets:
            - name: \$SECRET_NAME
          " >/dev/null
            echo -n "."
          done
          echo "OK"
        fi
        
        SECRET_NAME="rox-api-token"
        if [ -n "\$ROX_API_TOKEN" ] && [ -n "\$ROX_ENDPOINT" ]; then
          echo -n "* \$SECRET_NAME secret: "
          kubectl create secret generic "\$SECRET_NAME" \
            --from-literal=rox-api-endpoint=\$ROX_ENDPOINT \
            --from-literal=rox-api-token=\$ROX_API_TOKEN \
            --dry-run=client -o yaml | kubectl apply --filename - --overwrite=true >/dev/null
          kubectl annotate secret "\$SECRET_NAME" "helm.sh/chart={{.Chart.Name}}-{{.Chart.Version}}" >/dev/null
          echo "OK"
        fi

        echo
        echo "Namespace is ready to execute {{ .Chart.Name }} pipelines"
      workingDir: /tmp
{{ end }}