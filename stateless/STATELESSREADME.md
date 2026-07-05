# Stateless SPIRE on Kubernetes — Step-by-Step

This guide walks through the **stateless** part of the demo: the same functional
scenario as the [stateful demo](../stateful/STATEFULREADME.md) — SPIRE Server,
SPIRE Agent, Envoy mTLS, and OPA authorization — but installed and operated
declaratively instead of with hand-written manifests and `spire-server entry
create` commands.

Two projects make this possible:

- **[spire-controller-manager](https://github.com/spiffe/spire-controller-manager)** —
  a Kubernetes operator that watches custom resources (`ClusterSPIFFEID`,
  `ClusterFederatedTrustDomain`, `ClusterStaticEntry`) and reconciles them into
  SPIRE registration entries. No more `kubectl exec ... spire-server entry
  create`.
- **[helm-charts-hardened](https://github.com/spiffe/helm-charts-hardened)** —
  the `spiffe/spire` Helm chart, which installs SPIRE Server, SPIRE Agent, the
  SPIFFE CSI driver, and the controller manager as a single, versioned release.

> ⬅️ For the project overview, see the main **[README.md](../README.md)**.

---

## What changes vs. the stateful demo

| | Stateful | Stateless |
|---|---|---|
| Install | Hand-written YAML (`kubectl apply -f ...`) | `helm install spiffe/spire` |
| Workload → agent socket | `hostPath` mount of `/run/spire/sockets` | SPIFFE CSI driver ephemeral volume (`csi.spiffe.io`) |
| Registration | `spire-server entry create ...` shell scripts | `ClusterSPIFFEID` custom resources, reconciled automatically |
| Upgrades | Manual manifest edits | `helm upgrade` |

The SPIRE Server itself is still a `StatefulSet` with its own datastore — that
part of SPIRE is inherently stateful. "Stateless" here refers to how
**workload registration** is managed: no imperative commands, no state to
replay by hand if a registration entry is lost — it's continuously reconciled
from the `ClusterSPIFFEID` resources living in Git.

---

## Prerequisites

- A running Kubernetes cluster (`kind`, `minikube`, or real) with `kubectl` configured
- [`helm`](https://helm.sh/docs/intro/install/) v3+

```bash
git clone https://github.com/marcel-haag/spire-demos.git
cd spire-demos/stateless/k8s
```

---

## Phase 0 — Quickstart: SPIRE via Helm

Directory: [`quickstart/`](k8s/quickstart)

Install the CRDs and the SPIRE stack (server, agent, SPIFFE CSI driver,
controller manager) as a Helm release:

```bash
helm repo add spiffe https://spiffe.github.io/helm-charts-hardened/
helm repo update spiffe

helm upgrade --install spire-crds spiffe/spire-crds -n spire --create-namespace
helm upgrade --install spire spiffe/spire -n spire -f quickstart/values.yaml
```

[`values.yaml`](k8s/quickstart/values.yaml) sets the trust domain and cluster
name, and turns off the chart's blanket "every pod gets an identity" default —
later phases register workloads explicitly instead.

Check that the agent attested to the server (no manual node registration entry
needed — the chart wires up `k8s_psat` node attestation out of the box):

```bash
kubectl get pods -n spire
kubectl logs -n spire spire-server-0 -c spire-server | grep "Agent attestation request completed"
```

### Register a workload — declaratively

Instead of `spire-server entry create`, apply a `ClusterSPIFFEID`:

```yaml
# quickstart/client-identity.yaml
apiVersion: spire.spiffe.io/v1alpha1
kind: ClusterSPIFFEID
metadata:
  name: client
spec:
  spiffeIDTemplate: "spiffe://{{ .TrustDomain }}/ns/{{ .PodMeta.Namespace }}/sa/{{ .PodSpec.ServiceAccountName }}/client"
  podSelector:
    matchLabels:
      app: client
```

```bash
kubectl apply -f quickstart/client-identity.yaml
kubectl apply -f quickstart/client-deployment.yaml
```

The controller manager reconciles this into a SPIRE registration entry as soon
as a matching pod appears — check the outcome:

```bash
kubectl get clusterspiffeid client -o jsonpath='{.status.stats}'
kubectl logs -n spire -l app=client
```

You should see an X.509-SVID for `spiffe://example.org/ns/spire/sa/default/client`,
with **zero imperative registration commands**.

Automated: `bash quickstart/scripts/set-env.sh`, cleanup: `bash quickstart/scripts/clean-env.sh`,
full check: `bash quickstart/test.sh`.

---

## Phase 2 — X.509-SVID + Envoy + mTLS

Directory: [`envoy-x509/`](k8s/envoy-x509) — full tutorial: [envoy-x509/README.md](k8s/envoy-x509/README.md)

Same scenario as the stateful demo (backend nginx + two Symbank frontends,
each with an Envoy sidecar doing SDS-based mTLS), but:

- Workload pods mount the agent socket via the SPIFFE CSI driver instead of a
  `hostPath` volume.
- Registration is three `ClusterSPIFFEID` resources in
  [`identities.yaml`](k8s/envoy-x509/identities.yaml) instead of a
  `create-registration-entries.sh` script full of `spire-server entry create`
  invocations.

```bash
bash envoy-x509/scripts/set-env.sh
```

## Phase 3 — OPA Authorization

Directory: [`envoy-opa/`](k8s/envoy-opa) — full tutorial: [envoy-opa/README.md](k8s/envoy-opa/README.md)

Adds an OPA sidecar to the backend for policy-based authorization on top of
the mTLS authentication from Phase 2. No SPIRE registration changes are
needed here — it reuses the identities from Phase 2 and only changes the
Envoy/OPA configuration.

```bash
bash envoy-opa/scripts/set-env.sh
```

---

## Cleanup

Each phase's `clean-env.sh` also tears down the phases underneath it:

```bash
bash envoy-opa/scripts/clean-env.sh    # tears down envoy-opa + envoy-x509 + SPIRE
```

---

## Troubleshooting

```bash
kubectl logs -n spire spire-server-0 -c spire-server
kubectl logs -n spire spire-server-0 -c spire-controller-manager
kubectl logs -n spire -l app=spire-agent
```

- **`ClusterSPIFFEID` has no effect:** check `kubectl get clusterspiffeid <name> -o yaml`
  under `status.stats` — `podsSelected: 0` means the `podSelector`/`namespaceSelector`
  didn't match anything; `entryFailures > 0` means the SPIRE server rejected the
  entry (check the controller manager logs).
- **CRD not found errors on `helm install spire`:** install `spiffe/spire-crds`
  first — the CRDs are a separate chart so they can be managed independently
  of the SPIRE release.
- **Workload never gets an SVID:** the SPIFFE CSI driver must be running on
  the node (`kubectl get pods -n spire -l app.kubernetes.io/name=spiffe-csi-driver`)
  and the workload's pod spec must mount a `csi: driver: csi.spiffe.io` volume.

---

## References

- [spire-controller-manager](https://github.com/spiffe/spire-controller-manager)
- [ClusterSPIFFEID CRD reference](https://github.com/spiffe/spire-controller-manager/blob/main/docs/clusterspiffeid-crd.md)
- [helm-charts-hardened](https://github.com/spiffe/helm-charts-hardened)
- [spire chart reference](https://github.com/spiffe/helm-charts-hardened/tree/main/charts/spire)
- [stateful demo (manual manifests, for comparison)](../stateful/STATEFULREADME.md)
