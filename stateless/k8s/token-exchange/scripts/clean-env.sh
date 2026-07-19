#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
EXAMPLEDIR="$(dirname "$DIR")"
K8SDIR="$(dirname "$EXAMPLEDIR")"

bb=$(tput bold) || true
nn=$(tput sgr0) || true
green=$(tput setaf 2) || true

echo "${bb}Deleting the login/token-exchange Jobs...${nn}"
kubectl delete -f "${EXAMPLEDIR}"/jobs/jacob-login-exchange-job.yaml --ignore-not-found
kubectl delete -f "${EXAMPLEDIR}"/jobs/alex-login-exchange-job.yaml --ignore-not-found

echo "${bb}Deleting the STS and resource server...${nn}"
kubectl delete -k "${EXAMPLEDIR}"/. --ignore-not-found

echo "${bb}Deleting sts/resource-server identities...${nn}"
kubectl delete -f "${EXAMPLEDIR}"/identities.yaml --ignore-not-found

echo "${bb}Deleting resources from the X.509 demo...${nn}"
bash "${K8SDIR}"/envoy-x509/scripts/clean-env.sh > /dev/null

echo "${green}Cleaning completed.${nn}"
