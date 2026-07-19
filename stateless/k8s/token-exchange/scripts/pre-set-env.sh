#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
EXAMPLEDIR="$(dirname "$DIR")"
K8SDIR="$(dirname "$EXAMPLEDIR")"

# Creates the envoy-x509 scenario (SPIRE via Helm + backend/frontend/frontend-2).
# frontend/frontend-2's ClusterSPIFFEIDs are reused unchanged by this phase.
bash "${K8SDIR}"/envoy-x509/scripts/set-env.sh
