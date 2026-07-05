#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

bb=$(tput bold) || true
nn=$(tput sgr0) || true
red=$(tput setaf 1) || true
green=$(tput setaf 2) || true

clean_env() {
    echo "${bb}Cleaning up...${nn}"
    bash "${DIR}"/scripts/clean-env.sh > /dev/null
}

trap clean_env EXIT

clean_env

bash "${DIR}"/scripts/set-env.sh

echo "${bb}Checking that the client workload received an X.509-SVID...${nn}"
CLIENT_POD=$(kubectl get pod -n spire -l app=client -o jsonpath='{.items[0].metadata.name}')
for ((i=0;i<30;i++)); do
    if kubectl logs -n spire "${CLIENT_POD}" 2>/dev/null | grep -qe "spiffe://example.org/ns/spire/sa/default/client"; then
        echo "${green}Success${nn}"
        exit 0
    fi
    sleep 1
done

echo "${red}Failed! Client workload did not receive the expected SVID.${nn}"
exit 1
