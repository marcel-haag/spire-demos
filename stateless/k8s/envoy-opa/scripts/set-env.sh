#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
EXAMPLEDIR="$(dirname "$DIR")"
K8SDIR="$(dirname "$EXAMPLEDIR")"

bb=$(tput bold) || true
nn=$(tput sgr0) || true
red=$(tput setaf 1) || true

wait_for_opa() {
    LOGLINE="Received 1 svid"

    for ((i=0;i<30;i++)); do
        if ! kubectl rollout status deployment/backend; then
            sleep 1
            continue
        fi
        if ! kubectl logs --tail=300 --selector=app=backend -c opa 2>/dev/null | grep -qe "Bundle loaded and activated successfully\|Initializing server"; then
            sleep 2
            echo "Waiting until OPA is ready..."
            continue
        fi
        echo "Backend + OPA ready."
        READY=1
        break
    done
    if [ -z "${READY}" ]; then
        echo "${red}Timed out waiting for backend/OPA to be ready.${nn}"
        exit 1
    fi
}

# Deploys the envoy-x509 scenario (SPIRE + backend/frontend/frontend-2 identities)
bash "${K8SDIR}"/envoy-x509/scripts/set-env.sh > /dev/null

echo "${bb}Applying the OPA authorization overlay on the backend...${nn}"
kubectl apply -k "${EXAMPLEDIR}"/k8s/. > /dev/null

kubectl rollout restart deployment/backend > /dev/null

echo "${bb}Waiting until backend + OPA are ready...${nn}"
wait_for_opa > /dev/null

echo "${bb}OPA Environment creation completed.${nn}"
