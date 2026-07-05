#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
EXAMPLEDIR="$(dirname "$DIR")"

bb=$(tput bold) || true
nn=$(tput sgr0) || true
red=$(tput setaf 1) || true

wait_for_envoy() {
    LOGLINE="DNS hosts have changed for backend-envoy"

    for ((i=0;i<30;i++)); do
        if ! kubectl rollout status deployment/backend; then
            sleep 1
            continue
        fi
        if ! kubectl rollout status deployment/frontend; then
            sleep 1
            continue
        fi
        if ! kubectl rollout status deployment/frontend-2; then
            sleep 1
            continue
        fi
        if ! kubectl logs --tail=300 --selector=app=frontend -c envoy | grep -qe "${LOGLINE}"; then
            sleep 5
            echo "Waiting until Envoy is ready..."
            continue
        fi
        echo "Workloads ready."
        WK_READY=1
        break
    done
    if [ -z "${WK_READY}" ]; then
        echo "${red}Timed out waiting for workloads to be ready.${nn}"
        exit 1
    fi
}

# Installs SPIRE (server, agent, CSI driver, controller manager) via Helm
bash "${DIR}"/pre-set-env.sh > /dev/null

echo "${bb}Registering backend/frontend/frontend-2 identities (ClusterSPIFFEID)...${nn}"
kubectl apply -f "${EXAMPLEDIR}"/identities.yaml > /dev/null

echo "${bb}Deploying backend, frontend and frontend-2 (app + Envoy sidecar)...${nn}"
kubectl apply -k "${EXAMPLEDIR}"/k8s/. > /dev/null

echo "${bb}Waiting until deployments and Envoy are ready...${nn}"
wait_for_envoy > /dev/null

echo "${bb}X.509 Environment creation completed.${nn}"
