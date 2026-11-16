# 7. Cert-Manager Installation

Rancher requires `cert-manager` to manage internal cluster certificates.
This guide shows how to install cert-manager version `1.21.3` in an air-gapped environment.

---

## 1. Verify Prerequisites

Before installing cert-manager, verify:

1. All three RKE2 nodes are `Ready`:
   ```bash
   kubectl get nodes
   ```
2. The cert-manager container images are loaded into your private registry `registry.infra.internal`.
3. You have the `cert-manager-1.21.3.tgz` chart file on your node or admin machine.

---

## 2. Install Cert-Manager with Helm

You can install cert-manager from the `.tgz` file or from your internal OCI registry.

### Method A: Install Using Local `.tgz` Chart File

Run this Helm command:

```bash
helm upgrade --install cert-manager ./cert-manager-1.21.3.tgz \
  --namespace cert-manager \
  --create-namespace \
  --set crds.enabled=true \
  --set image.repository=registry.infra.internal/rancher/containers/cert-manager-controller \
  --set webhook.image.repository=registry.infra.internal/rancher/containers/cert-manager-webhook \
  --set cainjector.image.repository=registry.infra.internal/rancher/containers/cert-manager-cainjector \
  --set startupapicheck.image.repository=registry.infra.internal/rancher/containers/cert-manager-startupapicheck
```

### Method B: Install Using OCI Registry (Hauler)

If you pushed the chart to your local registry using Hauler:

```bash
helm upgrade --install cert-manager oci://registry.infra.internal/rancher/hauler/cert-manager \
  --version 1.21.3 \
  --namespace cert-manager \
  --create-namespace \
  --set global.imageRegistry=registry.infra.internal/rancher \
  --set crds.enabled=true
```

---

## 3. Verify the Installation

1. Check that the Custom Resource Definitions (CRDs) exist:
   ```bash
   kubectl get crd | grep cert-manager
   ```
   You should see:
   - `certificates.cert-manager.io`
   - `certificaterequests.cert-manager.io`
   - `issuers.cert-manager.io`
   - `clusterissuers.cert-manager.io`

2. Check the cert-manager pods:
   ```bash
   kubectl get pods -n cert-manager
   ```
   Output:
   ```text
   NAME                                       READY   STATUS    RESTARTS   AGE
   cert-manager-7d9fc8f55c-abc12              1/1     Running   0          60s
   cert-manager-cainjector-65c7bbf6d8-xyz34   1/1     Running   0          60s
   cert-manager-webhook-5475685888-def56      1/1     Running   0          60s
   ```

Wait until all three pods show status `Running` before you install Rancher Prime.
