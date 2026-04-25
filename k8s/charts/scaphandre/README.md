# scaphandre (vendored)

This is a vendored copy of the upstream Helm chart at
[hubblo-org/scaphandre `v1.0.2`](https://github.com/hubblo-org/scaphandre/tree/v1.0.2/helm/scaphandre)
with the deprecated `policy/v1beta1` `PodSecurityPolicy` removed:

- `templates/psp.yaml` is omitted.
- `templates/rbac.yaml` no longer grants `use` on the PSP.

## Why is this vendored?

The upstream chart gates its PSP with
`{{- if .Capabilities.APIVersions.Has "policy/v1beta1" }}`. With Helm 3 +
ArgoCD on a Kubernetes / K3s cluster ≥ 1.25 (where PSP no longer exists)
this gate still evaluates to `true`, because:

- Helm's `--api-versions` flag *appends* to its compiled-in scheme, it
  doesn't replace it ([argo-cd#7291](https://github.com/argoproj/argo-cd/issues/7291),
  Helm `--strict-api-versions` was rejected upstream).
- ArgoCD does not yet support arbitrary Helm post-renderers
  ([argo-cd#3698](https://github.com/argoproj/argo-cd/issues/3698)).
- Kustomize's `helmCharts` inflator (`--enable-helm`) only works against
  charts published to an HTTP or OCI Helm repository. Scaphandre is only
  shipped as files in the upstream git tree, so that route is not
  available.

The canonical upstream fix (used by prometheus-community, grafana,
cert-manager, fluxcd, …) is to change the gate to the kind-specific
form `Has "policy/v1beta1/PodSecurityPolicy"`. As long as upstream
hasn't merged that, vendoring is the simplest robust workaround.

## Bumping

```bash
ver=v1.0.2  # set the new tag
cd k8s/charts/scaphandre
for f in Chart.yaml values.yaml; do
  curl -fsSL "https://raw.githubusercontent.com/hubblo-org/scaphandre/${ver}/helm/scaphandre/$f" -o "$f"
done
for f in _helpers.tpl daemonset.yaml rbac.yaml service-account.yaml service.yaml servicemonitor.yaml; do
  curl -fsSL "https://raw.githubusercontent.com/hubblo-org/scaphandre/${ver}/helm/scaphandre/templates/$f" -o "templates/$f"
done
# Re-apply the PSP-rule deletion in templates/rbac.yaml
```

If upstream ever fixes the API gate, this whole directory can be
deleted and the ArgoCD `scaphandre` Application can point back at
`https://github.com/hubblo-org/scaphandre.git`.
