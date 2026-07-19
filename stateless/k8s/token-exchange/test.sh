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

prompt_cleanup() {
    printf "%sEverything is up and running. Want to run a cleanup now? [y/N]%s " "${bb}" "${nn}"
    read -r answer || answer=""
    case "$answer" in
        [Yy]*) clean_env ;;
        *) echo "Skipping cleanup. Workloads are left running — clean them up later with:${nn}  bash ${DIR}/scripts/clean-env.sh" ;;
    esac
}

echo "${bb}Cleaning up any previous run...${nn}"
clean_env

# set-env.sh brings up SPIRE + envoy-x509 + the STS/resource-server, runs the
# jacob/alex login+token-exchange Jobs, and already fails if either Job doesn't
# reach "Complete" (the Jobs assert their own act/sub claims internally).
bash "${DIR}"/scripts/set-env.sh

FAILED=0
for who in jacob alex; do
    if kubectl logs "job/${who}-login-exchange" -c login-exchange | grep -q "^SUCCESS:"; then
        echo "${green}${who}-login-exchange: human subject preserved, actor recorded, verified by the resource server${nn}"
    else
        echo "${red}${who}-login-exchange: did not report success${nn}"
        FAILED=1
    fi
done

if [ "${FAILED}" -eq 0 ]; then
    echo "${green}Success${nn}"
    prompt_cleanup
    exit 0
fi

echo "${red}Failed! Token exchange flow did not behave as expected.${nn}"
prompt_cleanup
exit 1
