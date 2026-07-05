#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
EXAMPLEDIR="$(dirname "$DIR")"
K8SDIR="$(dirname "$EXAMPLEDIR")"

bb=$(tput bold) || true
nn=$(tput sgr0) || true
green=$(tput setaf 2) || true

echo "${bb}Installing SPIRE (server, agent, SPIFFE CSI driver, controller manager) via Helm...${nn}"
bash "${K8SDIR}"/quickstart/scripts/set-env.sh

echo "${green}SPIRE resources creation completed.${nn}"
