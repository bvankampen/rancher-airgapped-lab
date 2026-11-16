# 6. RKE2 Air-Gapped Cluster Installation

In this step, you will install the 3-node RKE2 Kubernetes cluster.
You start with Node 1 to initialize etcd and the control plane.
Then, you join Node 2 and Node 3.

---

## 1. Create Required Directories

Run this on all three nodes (`rke2-server-01`, `rke2-server-02`, and `rke2-server-03`):

```bash
mkdir -p /etc/rancher/rke2
mkdir -p /var/lib/rancher/rke2/server/manifests
mkdir -p /var/lib/rancher/rke2/agent/images
mkdir -p /opt/rke2/artifacts
```

---

## 2. Copy Installation Files to Nodes

Copy the downloaded RKE2 artifacts into `/opt/rke2/artifacts/` on every node:

- `install.sh`
- `rke2.linux-amd64.tar.gz`
- `sha256sum-amd64.txt`
- `rke2-images.linux-amd64.tar.zst`
- `rke2-images-cilium.linux-amd64.tar.zst`

Also copy the image archives directly to the RKE2 agent image directory:

```bash
cp /opt/rke2/artifacts/rke2-images*.tar.zst /var/lib/rancher/rke2/agent/images/
chmod +x /opt/rke2/artifacts/install.sh
```

---

## 3. Create Cluster Configuration Files

Perform these configuration steps on **all three nodes** (`rke2-server-01`, `rke2-server-02`, and `rke2-server-03`) before starting the RKE2 service.

### Step 3.1: Create Pod Security Admission Configuration

Because we use the `cis` profile, Kubernetes enforces Pod Security Standards.
Create `/etc/rancher/rke2/rancher-psact.yaml`:

```bash
cat <<'EOF' > /etc/rancher/rke2/rancher-psact.yaml
apiVersion: apiserver.config.k8s.io/v1
kind: AdmissionConfiguration
plugins:
  - name: PodSecurity
    configuration:
      apiVersion: pod-security.admission.config.k8s.io/v1
      kind: PodSecurityConfiguration
      defaults:
        enforce: "restricted"
        enforce-version: "latest"
        audit: "restricted"
        audit-version: "latest"
        warn: "restricted"
        warn-version: "latest"
      exemptions:
        namespaces:
          - cattle-fleet-local-system
          - cattle-fleet-system
          - cattle-scc-system
          - cattle-system
          - kube-system
        runtimeClasses: []
        usernames: []
EOF
```

### Step 3.2: Create Private Registry Configuration (registries.yaml)

In an air-gapped environment, RKE2 containerd uses `/etc/rancher/rke2/registries.yaml` to route image pulls to your internal private registry (`registry.infra.internal`).
It provides TLS trust for your private CA and rewrite rules for upstream image namespaces.

Create `/etc/rancher/rke2/registries.yaml` on **all three nodes**:

```bash
cat <<'EOF' > /etc/rancher/rke2/registries.yaml
configs:
  registry.infra.internal:
    tls:
      ca_file: "/etc/pki/ca-trust/source/anchors/root-ca.pem"

mirrors:
  dp.apps.rancher.io:
    endpoint:
      - "https://registry.infra.internal"
    rewrite:
      "(.*)": "dp.apps.rancher.io/$1"
  registry.rancher.com:
    endpoint:
      - "https://registry.infra.internal"
    rewrite:
      "(.*)": "registry.rancher.com/$1"
  registry.suse.com:
    endpoint:
      - "https://registry.infra.internal"
    rewrite:
      "(.*)": "registry.suse.com/$1"
  docker.io:
    endpoint:
      - "https://registry.infra.internal"
  registry.k8s.io:
    endpoint:
      - "https://registry.infra.internal"
  quay.io:
    endpoint:
      - "https://registry.infra.internal"
EOF
```

### Step 3.3: Configure Cilium Operator Replicas (HelmChartConfig)

RKE2 installs Cilium CNI automatically.
You can customize chart settings by placing a `HelmChartConfig` manifest into `/var/lib/rancher/rke2/server/manifests/`.
By default, the Cilium operator runs 2 replicas.
In a 3-node cluster, you can explicitly configure the replica count by creating `/var/lib/rancher/rke2/server/manifests/rke2-cilium-config.yaml` on **all three nodes**:

```bash
cat <<'EOF' > /var/lib/rancher/rke2/server/manifests/rke2-cilium-config.yaml
---
apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: rke2-cilium
  namespace: kube-system
spec:
  valuesContent: |-
    operator:
      replicas: 1
EOF
```

*(Note: For larger production clusters, you can set `replicas: 2` for high availability).*

---

## 4. Install RKE2 on First Node (rke2-server-01)

Log in to the first node (`192.168.98.11`).

### Step 4.1: Create Server Config File

Create `/etc/rancher/rke2/config.yaml`:

```bash
cat <<'EOF' > /etc/rancher/rke2/config.yaml
token: "changethistoarandomvalue"
cni: "cilium"
profile: "cis"
selinux: true
pod-security-admission-config-file: "/etc/rancher/rke2/rancher-psact.yaml"
system-default-registry: "registry.rancher.com"
prime: true
tls-san:
  - "rancher.infra.internal"
  - "192.168.98.10"
  - "192.168.98.11"
  - "rke2-server-01"
EOF
```

*(Note: Change the `token` string to your own secret password. Keep it safe).*
*(Note: `system-default-registry: "registry.rancher.com"` routes through your local registry via `registries.yaml`).*

### Step 4.2: Run the Installer Script

Run the installation script in offline tar mode:

```bash
INSTALL_RKE2_ARTIFACT_PATH="/opt/rke2/artifacts" \
INSTALL_RKE2_TYPE="server" \
INSTALL_RKE2_METHOD="tar" \
/opt/rke2/artifacts/install.sh
```

### Step 4.3: Start RKE2 Service

Enable and start the service:

```bash
systemctl enable --now rke2-server
```

Watch the service logs until it finishes starting:

```bash
journalctl -u rke2-server -f
```

### Step 4.4: Verify the First Node

After 2 to 3 minutes, check the node status:

```bash
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
/var/lib/rancher/rke2/bin/kubectl get nodes -o wide
```

Output should show `rke2-server-01` in status `Ready`:
```text
NAME              STATUS   ROLES                       AGE     VERSION
rke2-server-01    Ready    control-plane,etcd,master   2m30s   v1.36.5+rke2r1
```

---

## 5. Join Node 2 and Node 3

Join additional nodes one by one. Ensure `rancher-psact.yaml`, `registries.yaml`, and `rke2-cilium-config.yaml` are already created on each node before starting the service.

### Step 5.1: Configure Node 2 (rke2-server-02)

Log in to `rke2-server-02` (`192.168.98.12`).
Create `/etc/rancher/rke2/config.yaml`:

```bash
cat <<'EOF' > /etc/rancher/rke2/config.yaml
server: "https://192.168.98.11:9345"
token: "changethistoarandomvalue"
cni: "cilium"
profile: "cis"
selinux: true
pod-security-admission-config-file: "/etc/rancher/rke2/rancher-psact.yaml"
system-default-registry: "registry.rancher.com"
prime: true
tls-san:
  - "rancher.infra.internal"
  - "192.168.98.10"
  - "192.168.98.12"
  - "rke2-server-02"
EOF
```

Run the installer:

```bash
INSTALL_RKE2_ARTIFACT_PATH="/opt/rke2/artifacts" \
INSTALL_RKE2_TYPE="server" \
INSTALL_RKE2_METHOD="tar" \
/opt/rke2/artifacts/install.sh
```

Start the service:

```bash
systemctl enable --now rke2-server
```

Wait until Node 2 is `Ready` before moving to Node 3.

---

### Step 5.2: Configure Node 3 (rke2-server-03)

Log in to `rke2-server-03` (`192.168.98.13`).
Create `/etc/rancher/rke2/config.yaml`:

```bash
cat <<'EOF' > /etc/rancher/rke2/config.yaml
server: "https://192.168.98.11:9345"
token: "changethistoarandomvalue"
cni: "cilium"
profile: "cis"
selinux: true
pod-security-admission-config-file: "/etc/rancher/rke2/rancher-psact.yaml"
system-default-registry: "registry.rancher.com"
prime: true
tls-san:
  - "rancher.infra.internal"
  - "192.168.98.10"
  - "192.168.98.13"
  - "rke2-server-03"
EOF
```

Run the installer:

```bash
INSTALL_RKE2_ARTIFACT_PATH="/opt/rke2/artifacts" \
INSTALL_RKE2_TYPE="server" \
INSTALL_RKE2_METHOD="tar" \
/opt/rke2/artifacts/install.sh
```

Start the service:

```bash
systemctl enable --now rke2-server
```

---

## 6. Verify the Full Cluster

On `rke2-server-01` (or any node with `kubectl` configured):

```bash
kubectl get nodes -o wide
```

Output:
```text
NAME              STATUS   ROLES                       AGE   VERSION
rke2-server-01    Ready    control-plane,etcd,master   15m   v1.36.5+rke2r1
rke2-server-02    Ready    control-plane,etcd,master   8m    v1.36.5+rke2r1
rke2-server-03    Ready    control-plane,etcd,master   3m    v1.36.5+rke2r1
```

Check all system pods:

```bash
kubectl get pods -A
```

All pods in `kube-system` must show `Running` or `Completed`.

---

## 7. Configure Kubeconfig for Admin Jump Host

To manage the cluster from your admin workstation:

1. Copy `/etc/rancher/rke2/rke2.yaml` from `rke2-server-01` to your workstation.
2. Edit the file on your workstation:
   - Change `server: https://127.0.0.1:6443` to `server: https://192.168.98.11:6443` (or `https://rancher.infra.internal:6443`).
   - Change the context name if you manage multiple clusters.
3. Test connectivity:
   ```bash
   kubectl --kubeconfig=./rke2.yaml get nodes
   ```
