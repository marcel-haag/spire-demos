#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
EXAMPLEDIR="$(dirname "$DIR")"

bb=$(tput bold) || true
nn=$(tput sgr0) || true
red=$(tput setaf 1) || true

# Deploys the envoy-x509 base scenario this phase builds on.
bash "${DIR}"/pre-set-env.sh > /dev/null

echo "${bb}Registering sts/resource-server identities (ClusterSPIFFEID)...${nn}"
kubectl apply -f "${EXAMPLEDIR}"/identities.yaml > /dev/null

echo "${bb}Deploying the STS (Keycloak + Envoy mTLS gate) and resource server...${nn}"
kubectl apply -k "${EXAMPLEDIR}"/. > /dev/null

echo "${bb}Waiting until the STS and resource server are ready...${nn}"
kubectl rollout status deployment/sts --timeout=180s
kubectl rollout status deployment/resource-server --timeout=90s

# Only start the login/exchange Jobs once the STS is actually ready — applying
# them earlier (e.g. as part of the kustomization above) races Keycloak's boot
# and can burn through the Jobs' backoffLimit before it comes up.
echo "${bb}Running the login/token-exchange Jobs (Jacob against frontend, Alex against frontend-2)...${nn}"
kubectl apply -f "${EXAMPLEDIR}"/jobs/jacob-login-exchange-job.yaml > /dev/null
kubectl apply -f "${EXAMPLEDIR}"/jobs/alex-login-exchange-job.yaml > /dev/null

echo "${bb}Waiting for the login/token-exchange Jobs to complete...${nn}"
if ! kubectl wait --for=condition=complete job/jacob-login-exchange --timeout=120s; then
    echo "${red}jacob-login-exchange did not complete in time:${nn}"
    kubectl logs job/jacob-login-exchange -c login-exchange || true
    exit 1
fi
if ! kubectl wait --for=condition=complete job/alex-login-exchange --timeout=120s; then
    echo "${red}alex-login-exchange did not complete in time:${nn}"
    kubectl logs job/alex-login-exchange -c login-exchange || true
    exit 1
fi

echo "${bb}Token exchange Environment creation completed.${nn}"
