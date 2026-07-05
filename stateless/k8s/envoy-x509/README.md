# Configure Envoy to Perform X.509 SVID Authentication (stateless)

This is the stateless counterpart of
[stateful/k8s/envoy-x509](../../../stateful/k8s/envoy-x509/README.md): the same
Envoy mTLS scenario, but SPIRE is installed via the `spiffe/spire` Helm chart
and workloads are registered with `ClusterSPIFFEID` custom resources instead
of `spire-server entry create` shell scripts. If you haven't already, skim the
[stateless overview](../../STATELESSREADME.md) first.

Three services are involved, same as the stateful demo: a backend `nginx`
instance serving static account data, and two instances of the `Symbank` demo
banking app (`frontend` and `frontend-2`) acting as HTTP clients. Envoy
sidecars on all three establish mTLS using X.509-SVIDs obtained from the SPIRE
Agent via SDS (Secret Discovery Service).

![SPIRE Envoy integration diagram][diagram]

[diagram]: images/SPIRE_Envoy_diagram.png "SPIRE Envoy integration diagram"

## Prerequisites

* A Kubernetes cluster with `kubectl` and `helm` configured.
* Optionally, run `bash scripts/pre-set-env.sh` to install SPIRE (server,
  agent, SPIFFE CSI driver, controller manager) via Helm — see
  [`quickstart/`](../quickstart) for what that installs.

### External IP support

Same as the stateful tutorial, this demo needs a LoadBalancer that can assign
an external IP (e.g. [metallb](https://metallb.universe.tf/)) if you want to
reach `frontend`/`frontend-2` from outside the cluster instead of via
`kubectl port-forward`:

```console
$ kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.7/config/manifests/metallb-native.yaml
$ kubectl wait --namespace metallb-system --for=condition=ready pod --selector=app=metallb --timeout=90s
$ kubectl apply -f metallb-config.yaml
```

## Part 1: Deploy the workloads

```console
$ kubectl apply -k k8s/.
```

This creates the same Deployments/Services/ConfigMaps as the stateful demo
(unchanged Envoy and app configuration). The one workload-manifest difference:
the agent socket is mounted through the SPIFFE CSI driver instead of a
`hostPath` volume —

```yaml
volumes:
  - name: spire-agent-socket
    csi:
      driver: "csi.spiffe.io"
      readOnly: true
```

— mounted at `/run/spire/agent-sockets`, matching the SPIRE Agent's default
`socketPath` in the Helm chart. Envoy's `spire_agent` cluster in
[`k8s/backend/config/envoy.yaml`](k8s/backend/config/envoy.yaml) points at
that same path.

## Part 2: Register the workloads

Instead of `create-registration-entries.sh`, apply
[`identities.yaml`](identities.yaml):

```yaml
apiVersion: spire.spiffe.io/v1alpha1
kind: ClusterSPIFFEID
metadata:
  name: backend
spec:
  spiffeIDTemplate: "spiffe://{{ .TrustDomain }}/ns/{{ .PodMeta.Namespace }}/sa/{{ .PodSpec.ServiceAccountName }}/backend"
  podSelector:
    matchLabels:
      app: backend
  workloadSelectorTemplates:
    - "k8s:container-name:envoy"
```

```console
$ kubectl apply -f identities.yaml
```

There's one `ClusterSPIFFEID` per workload (`backend`, `frontend`,
`frontend-2`). All three pods share the same namespace and service account
(`default`), so the app name has to come from the pod label via the template
rather than from `{{ .PodSpec.ServiceAccountName }}` alone — otherwise all
three workloads would collide on the same SPIFFE ID.
`workloadSelectorTemplates: ["k8s:container-name:envoy"]` scopes the identity
to the Envoy sidecar container specifically, mirroring the original
`-selector k8s:container-name:envoy` registration entries.

The controller manager reconciles these into SPIRE registration entries
automatically — no `spire-server entry create` involved:

```console
$ kubectl get clusterspiffeid -o custom-columns=NAME:.metadata.name,ENTRIES:.status.stats.entriesToSet,FAILURES:.status.stats.entryFailures
$ kubectl exec -n spire spire-server-0 -c spire-server -- /opt/spire/bin/spire-server entry show
```

## Part 3: Test connections

```console
$ kubectl port-forward svc/frontend 3000:3000 &
$ curl -s http://127.0.0.1:3000/ | grep "balance"
```

You should see _Jacob Marley_'s balance (10.95). Same for `frontend-2` on port
3002 (`Alex Fergus`). Both reach the backend over mTLS, each side presenting
its SPIRE-issued X.509-SVID.

### Restrict the backend to a single frontend

Same optional exercise as the stateful tutorial: apply
[`backend-envoy-configmap-update.yaml`](backend-envoy-configmap-update.yaml)
to narrow the backend's `match_typed_subject_alt_names` to only accept
`frontend`, then restart the backend deployment. `frontend-2` will then get
rejected at the TLS layer even though nothing about its SPIRE identity
changed — only the backend's Envoy configuration.

```console
$ kubectl apply -f backend-envoy-configmap-update.yaml
$ kubectl rollout restart deployment backend
```

An Envoy RBAC HTTP filter variant of the same idea is in
[`backend-envoy-configmap-rbac-update.yaml`](backend-envoy-configmap-rbac-update.yaml).

## Cleanup

```console
$ bash scripts/clean-env.sh
```

Removes the workloads, the `ClusterSPIFFEID` resources, and (via
`quickstart/scripts/clean-env.sh`) the Helm-installed SPIRE stack and the
`spire` namespace.

## Automated

```console
$ bash test.sh
```

Installs SPIRE, registers and deploys the workloads, curls the frontend for
the expected balance, then tears everything down.

## References

- [Stateful envoy-x509 tutorial (manual manifests)](../../../stateful/k8s/envoy-x509/README.md)
- [ClusterSPIFFEID CRD reference](https://github.com/spiffe/spire-controller-manager/blob/main/docs/clusterspiffeid-crd.md)
- [spire chart (helm-charts-hardened)](https://github.com/spiffe/helm-charts-hardened/tree/main/charts/spire)
