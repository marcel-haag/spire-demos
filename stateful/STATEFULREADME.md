# Stateful SPIRE on Kubernetes — Step-by-Step

This guide walks through the **stateful** part of the demo: a SPIRE Server running
as a `StatefulSet` (holding registration entries, trust bundle, and CA state),
SPIRE Agents as a `DaemonSet`, manual workload registration, fetching an X.509-SVID
via the SPIFFE Workload API, and then securing traffic with **Envoy mTLS** and
**OPA authorization**.

It is based on the official
[Getting Started on Kubernetes](https://spiffe.io/docs/latest/try/getting-started-k8s/)
tutorial and the [spiffe/spire-tutorials](https://github.com/spiffe/spire-tutorials)
repository, adapted for this demo.

> ⬅️ For the project overview and the stateless roadmap, see the main
> **[README.md](./README.md)**.

---

## What's in the stateful setup

- **Database** — persistent application data
- **SPIRE Server** (`StatefulSet`) — registration entries, trust bundle, CA state
- **SPIRE Agent** (`DaemonSet`) — Workload API on every node
- **Frontend** and **Backend** services
- **Envoy sidecar** — mTLS via SPIRE-issued certs (SDS)
- **OPA sidecar** — external authorization for Envoy
- **Demo app** without persistent data

---

## Concepts you'll see in action

- **SPIRE Server** — the trust root. Signs SVIDs, stores registration entries, CA.
- **SPIRE Agent** — runs on each node, exposes the **Workload API** over a Unix
  domain socket, attests workloads, and delivers their SVIDs.
- **Node attestation** — how the server verifies *which node* an agent is on
  (e.g. `k8s_psat`).
- **Workload attestation** — how the agent verifies *which workload* is calling
  (e.g. by Kubernetes namespace + service account).
- **Registration entry** — a rule: *a workload matching these selectors gets this
  SPIFFE ID.*
- **SPIFFE ID vs. X.509-SVID** — the SPIFFE ID is the identity *name*
  (`spiffe://…`); the X.509-SVID is the short-lived *certificate* proving it.

---

## Prerequisites

<!-- TODO: confirm against what you tested -->
- A running Kubernetes cluster (`kind`, `minikube`, or real)
- `kubectl` configured for that cluster

```bash
git clone https://github.com/marcel-haag/spire-demos.git
cd spire-demos
```

---

## Phase 0 / 1 — SPIRE foundation

### 1. Create the namespace

<!-- TODO: replace manifest filenames throughout with your actual files -->
```bash
kubectl apply -f spire-namespace.yaml
kubectl get namespaces
```

### 2. Deploy the SPIRE Server (StatefulSet)

The server runs as a `StatefulSet` with stable identity and persistent storage for
its datastore (registration entries, trust bundle, CA state).

```bash
kubectl apply \
  -f server-account.yaml \
  -f spire-bundle-configmap.yaml \
  -f server-cluster-role.yaml \
  -f server-configmap.yaml \
  -f server-statefulset.yaml \
  -f server-service.yaml

kubectl get statefulset -n spire
kubectl get pods -n spire
```

### 3. Deploy the SPIRE Agent (DaemonSet)

One agent per node, so any pod can reach a local Workload API socket.

```bash
kubectl apply \
  -f agent-account.yaml \
  -f agent-cluster-role.yaml \
  -f agent-configmap.yaml \
  -f agent-daemonset.yaml
```

Confirm node attestation succeeded:

```bash
kubectl exec -n spire spire-server-0 -- \
  /opt/spire/bin/spire-server agent list
```

You should see one attested agent per node.

### 4. Register a workload (Registration Entry)

First a **node** entry (so agents can attest), then a **workload** entry.

<!-- TODO: adjust trust domain, cluster name, selectors, namespaces, SAs to yours -->

```bash
# Node entry
kubectl exec -n spire spire-server-0 -- \
  /opt/spire/bin/spire-server entry create \
    -spiffeID spiffe://example.org/ns/spire/sa/spire-agent \
    -selector k8s_psat:cluster:demo-cluster \
    -selector k8s_psat:agent_ns:spire \
    -selector k8s_psat:agent_sa:spire-agent \
    -node
```

```bash
# Workload entry (e.g. backend)
kubectl exec -n spire spire-server-0 -- \
  /opt/spire/bin/spire-server entry create \
    -spiffeID spiffe://example.org/ns/default/sa/backend \
    -parentID spiffe://example.org/ns/spire/sa/spire-agent \
    -selector k8s:ns:default \
    -selector k8s:sa:backend
```

List entries:

```bash
kubectl exec -n spire spire-server-0 -- \
  /opt/spire/bin/spire-server entry show
```

> **Why this workload gets this identity:** the agent attests the calling pod
> against Kubernetes selectors (namespace + service account). When those match an
> entry's selectors, SPIRE issues the corresponding SPIFFE ID — no shared secret,
> no manual cert handling.

### 5. Fetch the X.509-SVID

```bash
kubectl exec -it <workload-pod> -- \
  /opt/spire/bin/spire-agent api fetch x509 \
    -socketPath /run/spire/sockets/agent.sock
```

You should see one or more **X.509-SVIDs** with the SPIFFE ID you registered.
SPIRE rotates these automatically before they expire.

Inspect the URI SAN (the SPIFFE ID inside the cert):

```bash
kubectl exec -it <workload-pod> -- \
  /opt/spire/bin/spire-agent api fetch x509 \
    -socketPath /run/spire/sockets/agent.sock -write /tmp/

kubectl exec -it <workload-pod> -- \
  openssl x509 -in /tmp/svid.0.pem -noout -text | grep -A1 "Subject Alternative Name"
```

---

## Phase 2 — Envoy + mTLS

Deploy the frontend and backend with **Envoy sidecars** that pull certificates
from the SPIRE Agent via **SDS**, and establish **mTLS** between them.

<!-- TODO: replace with your real manifests / paths -->
```bash
kubectl apply -f db-deployment.yaml
kubectl apply -f backend-deployment.yaml      # app + Envoy sidecar
kubectl apply -f frontend-deployment.yaml     # app + Envoy sidecar
```

Verify:
- Frontend ↔ Backend traffic is **mTLS**, with each side presenting its SPIFFE ID.
- Certificates **rotate** automatically (no restart needed).
- A workload with an **unknown or wrong identity** is **rejected** at the TLS layer.

```bash
# TODO: add the exact curl/port-forward commands you use to demonstrate this
```

---

## Phase 3 — OPA Authorization

Add an **OPA sidecar** as Envoy's external authorization service. Envoy handles
**authentication** (verified SPIFFE ID via mTLS); OPA handles **authorization**
(is this SPIFFE ID allowed to perform this HTTP method on this path?).

<!-- TODO: replace with your real OPA policy + manifests -->
```bash
kubectl apply -f opa-config.yaml          # OPA + policy
kubectl apply -f backend-with-opa.yaml    # backend + Envoy ext_authz → OPA
```

Demonstrate:
- A request from an **allowed** SPIFFE ID to a permitted method/path → **200**.
- A request from an **authenticated but unauthorized** SPIFFE ID → **403**.
- Policy decisions are based on **SPIFFE ID + HTTP method + path**.

```bash
# TODO: add the exact requests showing allow vs. deny
```

> **Separation of concerns:** authentication (mTLS / SPIFFE ID) proves *who* the
> caller is; authorization (OPA policy) decides *what* they may do. The two are
> independent layers.

---

## Cleanup

<!-- TODO: adjust to whatever you actually created -->
```bash
kubectl delete namespace spire
kubectl delete -f backend-deployment.yaml -f frontend-deployment.yaml -f db-deployment.yaml
```

---

## Troubleshooting

```bash
kubectl logs -n spire spire-server-0
kubectl logs -n spire -l app=spire-agent
```

- **Agent not attesting:** check the node entry selectors match your cluster name /
  namespace / service account exactly.
- **Workload gets no SVID:** confirm the pod mounts the Workload API socket and its
  namespace + service account match a registration entry.
- **mTLS fails:** check Envoy's SDS config points at the agent socket and the
  expected SPIFFE IDs.
- **OPA always denies:** check the policy package/path and the input Envoy sends
  (SPIFFE ID, method, path).

---

## References

- [Getting Started on Kubernetes](https://spiffe.io/docs/latest/try/getting-started-k8s/)
- [spiffe/spire-tutorials](https://github.com/spiffe/spire-tutorials)
- [Envoy X.509 SDS tutorial](https://github.com/spiffe/spire-tutorials/tree/main/k8s/envoy-x509)
- [Envoy + OPA tutorial](https://github.com/spiffe/spire-tutorials/tree/main/k8s/envoy-opa)
- [SPIRE concepts](https://spiffe.io/docs/latest/spire-about/)