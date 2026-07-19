# OAuth 2.0 Token Exchange / On-Behalf-Of, with SPIFFE X.509-SVIDs as the actor credential

This phase builds on [envoy-x509](../envoy-x509/README.md) to answer a
question the earlier phases don't: when `frontend` calls a downstream
resource *on behalf of* a human (Jacob Marley), how do you prove **both**
"this is Jacob Marley's request" **and** "this is the `frontend` workload
acting" — without either fact getting lost?

This is the [RFC 8693 OAuth 2.0 Token Exchange](https://datatracker.ietf.org/doc/html/rfc8693)
pattern: a `sub` claim that stays the human's, and an `act` claim that
records the acting workload. [Keycloak](https://www.keycloak.org/) acts as
the Authorization Server / Security Token Service (STS); SPIRE-issued
X.509-SVIDs (via the same Envoy-SDS-mTLS pattern as `envoy-x509`) prove which
workload is talking to it.

```
frontend/frontend-2 pod label (app=frontend / app=frontend-2)
        │  (reused, already registered by envoy-x509/identities.yaml)
        ▼
┌────────────────────────┐        ┌────────────────────────────┐
│ login-exchange Job      │  mTLS  │ sts (Keycloak + Envoy)      │
│ pod carries the SAME    │───────▶│ Envoy: SPIRE SDS, SAN       │
│ SPIFFE ID as the real   │        │ allow-list = frontend,      │
│ frontend workload       │        │ frontend-2, resource-server │
│ 1. ROPC login as human  │        │ Keycloak: realm import,     │
│ 2. self token-exchange  │        │ per-client hardcoded         │
└────────────────────────┘        │ act.sub mapper, standard     │
        │                          │ token exchange enabled       │
        │ Bearer <exchanged token> └────────────────────────────┘
        ▼
┌─────────────────────────────┐
│ resource-server               │
│ Envoy: jwt_authn filter,      │
│ verifies against Keycloak     │
│ JWKS (fetched via mTLS),      │
│ forwards payload as a header  │
│ nginx: echoes the header       │
└─────────────────────────────┘
```

No custom application code is introduced anywhere in this phase — Keycloak
does the OAuth mechanics, and Envoy filters (SDS mTLS, `jwt_authn`) do
everything else, the same way Envoy's SDS and `ext_authz` filters carried
`envoy-x509` and `envoy-opa`.

## Two simplifications, on purpose

Keycloak has two gaps relative to what a "pure" implementation of this
pattern would need. Both are deliberate, documented trade-offs rather than
oversights:

1. **Keycloak's Standard Token Exchange (V2, officially supported since
   26.2) does not implement RFC 8693 delegation.** It accepts no
   `actor_token` parameter and never sets `act` itself — that's on
   Keycloak's roadmap, not shipped. Instead, `frontend` and `frontend-2`
   each get their own confidential Keycloak client with a **hardcoded
   protocol-mapper claim** (`act.sub` = that workload's SPIFFE ID, see
   [`keycloak/realm-export.json`](keycloak/realm-export.json)). Each client
   does a **self-exchange** — exchanging a token it already issued to
   itself, which Standard Token Exchange V2 explicitly exempts from its
   "subject_token's `aud` must contain the requester client" rule, so no
   extra permission wiring is needed either. The result has the RFC 8693
   shape (`sub` = human, `act.sub` = workload), produced through static
   per-client config rather than genuine dynamic actor-token processing.
2. **Keycloak cannot authenticate clients using SPIFFE X.509-SVID URI
   SANs** (there's an [open feature request](https://github.com/keycloak/keycloak/issues/41907),
   not shipped). So Keycloak itself stays SPIFFE-unaware; the mTLS
   enforcement happens one layer down, via an Envoy sidecar in front of it
   doing SPIRE-SDS mTLS with a SAN allow-list — the exact same mechanism
   `backend` already uses in `envoy-x509`.

## Prerequisites

* `envoy-x509` running (or `bash scripts/pre-set-env.sh` brings it up).
* **Enough memory for the cluster.** Keycloak's JVM needs real headroom on
  top of SPIRE + several Envoy sidecars + the Symbank apps. If you're on
  `kind` + podman on macOS, size the podman machine to at least 4 GiB
  (this was built and tested against 6 GiB after hitting a kernel-level
  OOM at 2 GiB):
  ```console
  $ podman machine stop
  $ podman machine set --memory 6144
  $ podman machine start
  ```

## Part 1: Deploy the STS and resource server

```console
$ bash scripts/pre-set-env.sh   # SPIRE + envoy-x509, if not already up
$ kubectl apply -f identities.yaml
$ kubectl apply -k .
$ kubectl rollout status deployment/sts
$ kubectl rollout status deployment/resource-server
```

[`keycloak/realm-export.json`](keycloak/realm-export.json) is imported at
Keycloak boot (`start-dev --import-realm`) and defines:
* realm `obo-demo`
* users `jacob.marley` / `alex.fergus` (the "human" identities)
* clients `frontend` / `frontend-2`, each confidential, with
  `directAccessGrantsEnabled` (for the simulated login) and
  `standard.token.exchange.enabled` (the client attribute behind the Admin
  Console's "Standard token exchange" toggle — confirmed by inspecting
  Keycloak's own shipped admin-ui bundle, since the docs don't spell out the
  exact JSON key), plus the hardcoded `act.sub` mapper described above.

[`keycloak/envoy-config/envoy.yaml`](keycloak/envoy-config/envoy.yaml) is the
mTLS gate: only `frontend`, `frontend-2`, and `resource-server` SPIFFE IDs
may reach Keycloak at all.

[`resource-server/envoy-config/envoy.yaml`](resource-server/envoy-config/envoy.yaml)
validates incoming Bearer tokens with the `jwt_authn` filter against
Keycloak's JWKS (fetched over the mTLS gate above, using the
`resource-server`'s own SPIFFE identity) and forwards the verified,
decoded payload to nginx as an `x-jwt-payload` header, which nginx echoes
back in the response (`add_header` in
[`resource-server/nginx.conf`](resource-server/nginx.conf)) — proving the
resource server saw a cryptographically checked `sub`/`act`, not merely
whatever the caller claimed.

## Part 2: Run the human-login + token-exchange flow

There's no real login UI — the Symbank frontend images are opaque, prebuilt
binaries — so a `Job` per human simulates it. Each Job's pod carries the
**same pod label** as its corresponding frontend (`app: frontend` /
`app: frontend-2`), so SPIRE issues it the identical SPIFFE ID via the
`ClusterSPIFFEID`s already defined in `envoy-x509/identities.yaml` — as far
as SPIRE is concerned, it *is* the frontend workload acting.

```console
$ kubectl apply -f jobs/jacob-login-exchange-job.yaml
$ kubectl apply -f jobs/alex-login-exchange-job.yaml
$ kubectl wait --for=condition=complete job/jacob-login-exchange --timeout=120s
$ kubectl wait --for=condition=complete job/alex-login-exchange --timeout=120s
$ kubectl logs job/jacob-login-exchange -c login-exchange
```

[`jobs/login-exchange.sh`](jobs/login-exchange.sh) does, over the Job's own
Envoy sidecar (mTLS to the STS):

1. **ROPC login** (`grant_type=password`) as `jacob.marley`, authenticated
   as the `frontend` client — the "human logs in" step.
2. **Self token-exchange** (`grant_type=urn:ietf:params:oauth:grant-type:token-exchange`),
   still authenticated as `frontend` — the "workload acts on the human's
   behalf" step.
3. Calls `resource-server` with the exchanged token as a Bearer token, and
   asserts the response's verified `sub`/`act.sub` match what's expected —
   this script doubles as the phase's test assertion.

Expected output (trimmed):
```
exchanged token claims: {"sub":"f8d0cc71-...","act":{"sub":"spiffe://example.org/ns/default/sa/default/frontend"}}
resource-server verified claims: {"sub":"f8d0cc71-...","act":{"sub":"spiffe://example.org/ns/default/sa/default/frontend"}}
SUCCESS: human sub 'f8d0cc71-...' preserved end to end, acting workload recorded as 'spiffe://example.org/ns/default/sa/default/frontend', cryptographically verified by the resource server.
```

Alex's run shows the same shape with `alex.fergus`'s `sub` and the
`frontend-2` SPIFFE ID.

## Verifying it's not just trusting the caller

Two checks worth running by hand to confirm the enforcement is real, not
cosmetic:

```console
# A token that isn't a valid JWT at all is rejected by jwt_authn (401):
$ kubectl run probe --image=badouralix/curl-jq:latest --restart=Never --command -- sleep 3600
$ kubectl exec probe -- curl -sS -D - -o /dev/null http://resource-server:9002/ \
    -H "Authorization: Bearer not.a.validtoken"
HTTP/1.1 401 Unauthorized

# A pod with no SPIFFE identity gets no response at all from the STS's mTLS gate:
$ kubectl exec probe -- curl -sS -m5 http://sts:8443/realms/obo-demo/.well-known/openid-configuration
curl: (52) Empty reply from server
$ kubectl delete pod probe
```

## Cleanup

```console
$ bash scripts/clean-env.sh
```

Removes the Jobs, the STS, the resource server, the `sts`/`resource-server`
identities, and (via `envoy-x509`'s `clean-env.sh`) the rest of the stack.

## Automated

```console
$ bash test.sh
```

Brings up SPIRE + envoy-x509 + this phase, runs both Jobs, checks both
report success, then tears everything down.

## References

- [RFC 8693 — OAuth 2.0 Token Exchange](https://datatracker.ietf.org/doc/html/rfc8693)
- [Keycloak: Configuring and using token exchange](https://www.keycloak.org/securing-apps/token-exchange)
- [Keycloak 26.2: Standard Token Exchange officially supported](https://www.keycloak.org/2025/05/standard-token-exchange-kc-26-2)
- [Envoy JWT authentication filter](https://www.envoyproxy.io/docs/envoy/latest/configuration/http/http_filters/jwt_authn_filter)
- [envoy-x509 (base scenario this phase reuses)](../envoy-x509/README.md)
