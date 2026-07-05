#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
QUICKSTARTDIR="$(dirname "$DIR")"

bb=$(tput bold) || true
nn=$(tput sgr0) || true
red=$(tput setaf 1) || true
green=$(tput setaf 2) || true

wait_for_agent() {
    for ((i=0;i<120;i++)); do
        if ! kubectl -n spire rollout status statefulset/spire-server 2>/dev/null; then
            sleep 1
            continue
        fi
        if ! kubectl -n spire rollout status daemonset/spire-agent 2>/dev/null; then
            sleep 1
            continue
        fi
        echo "${bb}SPIRE Server and Agent ready.${nn}"
        RUNNING=1
        break
    done
    if [ -z "${RUNNING}" ]; then
        echo "${red}Timed out waiting for SPIRE Server/Agent to be running.${nn}"
        exit 1
    fi
}

echo "${bb}Adding the spiffe Helm repo...${nn}"
helm repo add spiffe https://spiffe.github.io/helm-charts-hardened/ > /dev/null
helm repo update spiffe > /dev/null

echo "${bb}Installing SPIRE CRDs (ClusterSPIFFEID, ClusterFederatedTrustDomain, ...)...${nn}"
helm upgrade --install spire-crds spiffe/spire-crds -n spire --create-namespace > /dev/null

echo "${bb}Installing the SPIRE stack (server, agent, SPIFFE CSI driver, controller manager) via Helm...${nn}"
helm upgrade --install spire spiffe/spire -n spire -f "${QUICKSTARTDIR}"/values.yaml > /dev/null

echo "${bb}Waiting until SPIRE Server and Agent are running...${nn}"
wait_for_agent

echo "${bb}Registering the demo client workload declaratively (ClusterSPIFFEID)...${nn}"
kubectl apply -f "${QUICKSTARTDIR}"/client-identity.yaml > /dev/null
kubectl apply -f "${QUICKSTARTDIR}"/client-deployment.yaml > /dev/null
kubectl -n spire rollout status deployment/client > /dev/null

echo "${green}SPIRE resources creation completed.${nn}"
