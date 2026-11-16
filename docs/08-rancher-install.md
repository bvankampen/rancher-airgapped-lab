# 8. Rancher Prime Installation

This guide walks you through installing SUSE Rancher Prime version `2.15.3` in your air-gapped cluster.

---

## 1. Create the cattle-system Namespace

Create the namespace where Rancher runs:

```bash
kubectl create namespace cattle-system
```

---

## 2. Create TLS and CA Certificate Secrets

Rancher requires the server TLS certificate for its Ingress and the Root CA certificate to validate connections.

### Step 2.1: Create the Ingress TLS Secret

Create the secret containing your server certificate (`tls.crt`) and private key (`tls.key`):

```bash
kubectl -n cattle-system create secret tls tls-rancher-ingress \
  --cert=tls.crt \
  --key=tls.key
```

### Step 2.2: Create the Private CA Secret

Create the secret named `tls-ca` containing your private Root CA certificate (`cacerts.pem`):

```bash
kubectl -n cattle-system create secret generic tls-ca \
  --from-file=cacerts.pem
```

Verify both secrets exist:

```bash
kubectl -n cattle-system get secrets tls-rancher-ingress tls-ca
```

---

## 3. Create the Helm values.yaml Configuration

Create a file named `values.yaml`:

```bash
cat <<'EOF' > values.yaml
hostname: rancher.infra.internal
replicas: 3
systemDefaultRegistry: registry.infra.internal
useBundledSystemChart: true
ingress:
  tls:
    source: secret
privateCA: true
EOF
```

### Explanation of Settings

- **`hostname`:** The full DNS name pointing to the HAProxy load balancer.
- **`replicas`:** Runs 3 Rancher pods for high availability across the three nodes.
- **`systemDefaultRegistry`:** Pulls all system container images from your private registry (`registry.infra.internal`).
- **`useBundledSystemChart`:** Uses the built-in charts inside the image so Rancher does not contact GitHub.
- **`ingress.tls.source: secret`:** Instructs Rancher Ingress to use the custom TLS certificate stored in the `tls-rancher-ingress` secret.
- **`privateCA: true`:** Instructs Rancher to use the Root CA certificate stored in the `tls-ca` secret.

---

## 4. Install Rancher Prime with Helm

Choose either method below.

### Method A: Install Using Local `.tgz` Chart Archive

Run the command pointing to the local chart file:

```bash
helm install rancher ./rancher-2.15.3.tgz \
  --namespace cattle-system \
  --values values.yaml
```

### Method B: Install Using OCI Registry (Mirror)

If you pushed the chart to your internal registry (as done in `helm/rancher/install.sh`):

```bash
helm install rancher oci://registry.infra.internal/rancher/rancher \
  --version 2.15.3 \
  --namespace cattle-system \
  --values values.yaml
```

---

## 5. Monitor Installation and Rollout

1. Watch the rollout progress:
   ```bash
   kubectl -n cattle-system rollout status deploy/rancher
   ```

2. Check the status of all three Rancher pods:
   ```bash
   kubectl -n cattle-system get pods -l app=rancher -o wide
   ```
   All pods should transition from `ContainerCreating` to `Running` (1/1):
   ```text
   NAME                       READY   STATUS    RESTARTS   AGE
   rancher-6b87649d8c-79l5h   1/1     Running   0          4m
   rancher-6b87649d8c-bflwt   1/1     Running   0          4m
   rancher-6b87649d8c-zsq2q   1/1     Running   0          4m
   ```

3. Check Rancher ingress:
   ```bash
   kubectl -n cattle-system get ingress
   ```

---

## 6. Access the Rancher Web UI

1. Open a web browser on a workstation inside the network.
2. Go to:
   ```text
   https://rancher.infra.internal
   ```
3. Retrieve the bootstrap administrator password:
   ```bash
   kubectl get secret --namespace cattle-system bootstrap-secret \
     -o go-template='{{.data.bootstrapPassword|base64decode}}{{ "\n" }}'
   ```
4. Log in using the username `admin` and the bootstrap password.
5. Set your new permanent administrator password.
6. Confirm the Rancher Server URL is set to `https://rancher.infra.internal`.

---

## 7. How to Upgrade Rancher (Future Reference)

When upgrading Rancher in an air-gapped environment later:

1. Download the new chart `.tgz` and push new images to your private registry.
2. Save your current values:
   ```bash
   helm get values rancher -n cattle-system -o yaml > values.yaml
   ```
3. Run the upgrade command (using local `.tgz` or internal OCI registry):
   ```bash
   # Option A: From local archive
   helm upgrade rancher ./rancher-<NEW_VERSION>.tgz \
     -n cattle-system \
     --values values.yaml

   # Option B: From internal OCI registry (matches upgrade.sh)
   helm upgrade rancher oci://registry.infra.internal/rancher/rancher \
     --version <NEW_VERSION> \
     -n cattle-system \
     --values values.yaml
   ```
4. Verify the new pods:
   ```bash
   kubectl -n cattle-system rollout status deploy/rancher
   ```
