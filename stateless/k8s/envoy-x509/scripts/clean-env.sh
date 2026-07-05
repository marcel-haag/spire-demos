#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
EXAMPLEDIR="$(dirname "$DIR")"
K8SDIR="$(dirname "$EXAMPLEDIR")"

bb=$(tput bold) || true
nn=$(tput sgr0) || true
green=$(tput setaf 2) || true

echo "${bb}Deleting backend, frontend and frontend-2 resources...${nn}"
kubectl delete -k "${EXAMPLEDIR}"/k8s/. --ignore-not-found

echo "${bb}Deleting backend/frontend/frontend-2 identities...${nn}"
kubectl delete -f "${EXAMPLEDIR}"/identities.yaml --ignore-not-found

echo "${bb}Deleting all the SPIRE resources available in the cluster...${nn}"
bash "${K8SDIR}"/quickstart/scripts/clean-env.sh

echo "${green}Cleaning completed.${nn}"
