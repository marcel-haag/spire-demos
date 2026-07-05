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
    [ -n "${PF2_PID}" ] && kill "${PF2_PID}" > /dev/null 2>&1 || true
}

trap clean_env EXIT

clean_env

bash "${DIR}"/scripts/set-env.sh

# The OPA policy (k8s/backend/config/opa-policy.rego) only allows the
# `frontend` SPIFFE ID to reach the backend. frontend-2 is authenticated
# (valid mTLS) but not authorized, and must be rejected with a 403.

kubectl port-forward svc/frontend 3000:3000 > /dev/null 2>&1 &
PF_PID=$!
kubectl port-forward svc/frontend-2 3002:3002 > /dev/null 2>&1 &
PF2_PID=$!
sleep 3

FAILED=0

if curl -s http://127.0.0.1:3000/ | grep -qe "10.95"; then
    echo "${green}frontend (authorized): allowed, as expected${nn}"
else
    echo "${red}frontend (authorized): was unexpectedly denied${nn}"
    FAILED=1
fi

if curl -s http://127.0.0.1:3002/ | grep -qe "10.95"; then
    echo "${red}frontend-2 (unauthorized): was unexpectedly allowed${nn}"
    FAILED=1
else
    echo "${green}frontend-2 (unauthorized): denied, as expected${nn}"
fi

if [ "${FAILED}" -eq 0 ]; then
    echo "${green}Success${nn}"
    exit 0
fi

echo "${red}Failed! OPA authorization did not behave as expected.${nn}"
exit 1
