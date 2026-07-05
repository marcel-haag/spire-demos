# Using SPIFFE X.509 IDs with Envoy and Open Policy Agent Authorization (stateless)

Stateless counterpart of
[stateful/k8s/envoy-opa](../../../stateful/k8s/envoy-opa/README.md): adds
[Open Policy Agent](https://www.openpolicyagent.org/) (OPA) as an Envoy
external-authorization sidecar on top of the
[stateless envoy-x509 demo](../envoy-x509/README.md). Read that one first —
this is a delta on top of it. Nothing here changes how SPIRE registration
works; it reuses the `ClusterSPIFFEID` identities from the envoy-x509 phase
unchanged. Only the backend's Envoy/OPA configuration changes.

![SPIRE Envoy OPA integration diagram][diagram]

[diagram]: images/SPIRE_Envoy_OPA_X509_diagram.png "SPIRE Envoy OPA integration diagram"

Envoy handles **authentication** (who is calling, proven by mTLS + SPIFFE ID);
OPA handles **authorization** (is this SPIFFE ID allowed to do this?). The two
are independent layers.

## Prerequisites

Either already have the envoy-x509 scenario running, or bootstrap it:

```console
$ bash scripts/pre-set-env.sh
```

This installs SPIRE via Helm and deploys backend/frontend/frontend-2 with
their `ClusterSPIFFEID` identities (see
[envoy-x509](../envoy-x509/README.md)), exactly as in that tutorial — no OPA
yet.

## Part 1: Add OPA to the backend

[`k8s/backend/backend-deployment.yaml`](k8s/backend/backend-deployment.yaml)
adds an OPA container as a sidecar to the backend pod:

```yaml
- name: opa
  image: openpolicyagent/opa:1.17.0-envoy-static
  args:
    - "run"
    - "--server"
    - "--config-file=/run/opa/opa-config.yaml"
    - "/run/opa/opa-policy.rego"
  ports:
    - containerPort: 8182 # Envoy ext_authz gRPC
    - containerPort: 8181 # OPA REST API
```

[`k8s/backend/config/envoy.yaml`](k8s/backend/config/envoy.yaml) adds an
`envoy.filters.http.ext_authz` HTTP filter pointing at `127.0.0.1:8182`, so
every request to the backend is checked against OPA before reaching nginx.

[`k8s/backend/config/opa-policy.rego`](k8s/backend/config/opa-policy.rego)
only allows the `frontend` SPIFFE ID (extracted from the `x-forwarded-client-cert`
header Envoy sets from the mTLS peer certificate) to `GET`
`/balances/*`, `/profiles/*`, or `/transactions/*`:

```rego
allow if {
    valid_path
    http_request.method == "GET"
    svc_spiffe_id == "spiffe://example.org/ns/default/sa/default/frontend"
}
```

Apply the overlay and restart the backend to pick it up:

```console
$ kubectl apply -k k8s/.
$ kubectl rollout restart deployment backend
```

## Part 2: Test authorization

```console
$ kubectl port-forward svc/frontend 3000:3000 &
$ curl -s http://127.0.0.1:3000/ | grep "balance"     # 200 — allowed
$ kubectl port-forward svc/frontend-2 3002:3002 &
$ curl -s http://127.0.0.1:3002/ | grep "balance"     # no data — denied by OPA
```

`frontend-2` completes the mTLS handshake fine (it's authenticated) but its
requests never reach nginx — OPA denies them because its SPIFFE ID doesn't
match the policy. Watch the decisions live:

```console
$ bash scripts/backend-opa-logs.sh
```

To flip which frontend is authorized, edit the policy interactively:

```console
$ bash scripts/backend-update-policy.sh
```

## Cleanup

```console
$ bash scripts/clean-env.sh
```

Removes the OPA overlay, then (via envoy-x509's and quickstart's
`clean-env.sh`) the workloads, identities, and the Helm-installed SPIRE stack.

## Automated

```console
$ bash test.sh
```

Brings up the full stack, asserts `frontend` is allowed and `frontend-2` is
denied, then tears everything down.

## References

- [Stateful envoy-opa tutorial](../../../stateful/k8s/envoy-opa/README.md)
- [Open Policy Agent](https://www.openpolicyagent.org/)
- [Envoy External Authorization filter](https://www.envoyproxy.io/docs/envoy/latest/configuration/http/http_filters/ext_authz_filter)
