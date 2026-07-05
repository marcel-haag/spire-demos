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
    [ -n "${PF_PID}" ] && kill "${PF_PID}" > /dev/null 2>&1 || true
}

trap clean_env EXIT

clean_env

bash "${DIR}"/scripts/set-env.sh

kubectl port-forward svc/frontend 3000:3000 > /dev/null 2>&1 &
PF_PID=$!
sleep 3

# The frontend fetches account data from the backend through mTLS-terminating
# Envoy sidecars. If the balance shows up, the request made it end to end
# through both proxies using SPIRE-issued X.509-SVIDs.
BALANCE_LINE="10.95"
if curl -s http://127.0.0.1:3000/ | grep -qe "${BALANCE_LINE}"; then
    echo "${green}Success${nn}"
    exit 0
fi

echo "${red}Failed! Request did not make it through the proxies.${nn}"
exit 1
