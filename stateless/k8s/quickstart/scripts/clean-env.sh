#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
QUICKSTARTDIR="$(dirname "$DIR")"

bb=$(tput bold) || true
nn=$(tput sgr0) || true
green=$(tput setaf 2) || true

echo "${bb}Deleting the client demo workload...${nn}"
kubectl delete -f "${QUICKSTARTDIR}"/client-deployment.yaml --ignore-not-found
kubectl delete -f "${QUICKSTARTDIR}"/client-identity.yaml --ignore-not-found

echo "${bb}Uninstalling the SPIRE Helm releases...${nn}"
helm uninstall spire -n spire > /dev/null 2>&1 || true
helm uninstall spire-crds -n spire > /dev/null 2>&1 || true

echo "${bb}Deleting the spire namespace...${nn}"
kubectl delete namespace spire --ignore-not-found

echo "${green}Cleaning completed.${nn}"
