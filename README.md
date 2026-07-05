# spire-demos

A demo collection for **stateful and stateless workload identity** using
**SPIRE, SPIFFE, Envoy, OPA, and Kubernetes**.

The project builds up step by step — from a minimal SPIRE installation to a full
**zero-trust setup** with cryptographic workload identity, mutual TLS, and
policy-based authorization. The stateful part is based in large part on the
official [spiffe/spire-tutorials](https://github.com/spiffe/spire-tutorials).

> **Idea:** secure service-to-service communication shouldn't rely on network
> location, shared secrets, or long-lived credentials. SPIFFE/SPIRE gives every
> workload a short-lived, automatically rotated, cryptographically verifiable
> identity (an SVID). This repo demonstrates that end to end.

---

## What is SPIFFE / SPIRE?

- **SPIFFE** (Secure Production Identity Framework For Everyone) is a set of open
  standards for issuing identities to workloads. An identity is a **SPIFFE ID**
  (e.g. `spiffe://example.org/ns/default/sa/backend`) carried in an **SVID** — an
  **X.509 certificate** or a **JWT**.
- **SPIRE** is the production-ready reference implementation. It runs a **SPIRE
  Server** (the trust root / signing authority) and **SPIRE Agents** (one per node)
  that attest workloads and deliver their SVIDs via the **Workload API**.

---

## Architecture

### Stateful part
The components that hold state and form the trust foundation:

- **Database** — persistent application data
- **SPIRE Server** — holds **registration entries**, the **trust bundle**, and
  **CA state** (the signing keys / datastore)
- **Frontend service**
- **Backend service**
- **Envoy sidecar** — terminates/originates mTLS using SPIRE-issued certs (SDS)
- **OPA sidecar** — external authorization for Envoy
- **Demo app** without persistent data

### Stateless part
The same scenario, installed and registered declaratively instead of by hand:

- **Operator** — [spire-controller-manager](https://github.com/spiffe/spire-controller-manager),
  reconciling `ClusterSPIFFEID` custom resources into SPIRE registration entries
- **Helm charts** — [helm-charts-hardened](https://github.com/spiffe/helm-charts-hardened)'s
  `spiffe/spire` chart, installing server, agent, SPIFFE CSI driver, and the
  controller manager as one release

---

## Phases

| Phase | Topic | Status |
|------:|-------|:------:|
| **0** | Quickstart: SPIRE on Kubernetes | ✅ |
| **1** | Kubernetes + SPIRE fundamentals | ✅ |
| **2** | X.509-SVID + Envoy + mTLS | ✅ |
| **3** | OPA authorization | ✅ |
| **+**  | Stateless: Operator + Helm re-implementation of phases 0–3 | ✅ |

### Phase 0 — Quickstart Kubernetes
Get SPIRE running and prove a workload can fetch its identity.
- Deploy the **SPIRE Server** as a `StatefulSet`
- Deploy the **SPIRE Agent** as a `DaemonSet`
- Create a workload **registration entry**
- Fetch an **X.509-SVID** through the SPIFFE Workload API

Reference: <https://spiffe.io/docs/latest/try/getting-started-k8s/>

➡️ Full step-by-step guide: **[STATEFULREADME.md](./stateful/STATEFULREADME.md)**

### Phase 1 — Kubernetes + SPIRE Fundamentals
Understand *how* identity is established and *why* a given pod gets a given identity.
- SPIRE Server, SPIRE Agent, Workload API
- **Node attestation** (proving which node an agent runs on)
- **Workload attestation** (proving which pod is asking)
- Registration entries
- SPIFFE ID vs. X.509-SVID
- *Why does a particular pod receive a particular identity?*

### Phase 2 — X.509-SVID + Envoy + mTLS
Use SPIRE-issued identities to secure traffic between services.
- SPIFFE ID naming
- **Envoy SDS** (Secret Discovery Service) integration
- Automatic certificate issuance and **rotation**
- **mTLS** between services
- Rejection of unknown or incorrect identities

### Phase 3 — OPA Authorization
Layer policy-based authorization on top of authenticated identity.
- **OPA** as an Envoy external authorization sidecar
- Policies based on **SPIFFE ID**, HTTP method, and path
- Clear separation of **authentication** (who are you?) and **authorization**
  (what may you do?)

### Phase + — Stateless: Operator + Helm
Re-implements phases 0–3 declaratively: SPIRE installed via the
`spiffe/spire` Helm chart, workloads registered with `ClusterSPIFFEID` custom
resources reconciled by the spire-controller-manager operator instead of
hand-written manifests and `spire-server entry create` scripts.

➡️ Full step-by-step guide: **[STATELESSREADME.md](./stateless/STATELESSREADME.md)**

---

## Repository layout

<!-- TODO: adjust to match your actual directory structure -->