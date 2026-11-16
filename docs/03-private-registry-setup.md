# 3. Private Registry Deployment (SUSE Private Registry)

This guide explains how to install a dedicated, standalone SUSE Private Registry (Harbor) on RKE2.
The private registry stores all container images inside the air-gapped network.
Nodes pull their system and workload images directly from this server.

---

## 1. System Requirements and Storage Setup

Log in to the registry server (`registry.infra.internal` at `192.168.98.5`) as `root`.

The registry server requires a dedicated filesystem mounted at `/data` to store container layers and database files.

1. Ensure the `/data` partition exists and has at least 200 GB available space:
   ```bash
   df -h /data
   ```

2. If `/data` does not exist, create the directory:
   ```bash
   mkdir -p /data
   chmod 755 /data
   ```

3. Ensure DNS or `/etc/hosts` resolves `registry.infra.internal` to `192.168.98.5`:
   ```bash
   getent hosts registry.infra.internal
   ```

---

## 2. Prepare the Registry Host Operating System

Perform basic OS hardening and network configuration before installing RKE2.

### Step 2.1: Create the etcd System User

```bash
useradd -r -c "etcd user" -s /sbin/nologin -M etcd -U
mkdir -p /var/lib/rancher/rke2/server/db/etcd
chown -R etcd:etcd /var/lib/rancher/rke2/server/db/etcd
chmod 700 /var/lib/rancher/rke2/server/db/etcd
```

### Step 2.2: Configure CIS sysctl Settings

```bash
cat <<'EOF' > /etc/sysctl.d/60-rke2-cis.conf
vm.panic_on_oom=0
vm.overcommit_memory=1
kernel.panic=10
kernel.panic_on_oops=1
EOF

sysctl --system
```

### Step 2.3: Configure the Host Firewall

Allow the required ports in `firewalld`:

```bash
systemctl enable --now firewalld

# Cilium, Kubelet, and HTTP/HTTPS Ingress
firewall-cmd --permanent --add-port=8472/udp
firewall-cmd --permanent --add-port=4240/tcp
firewall-cmd --permanent --add-port=10250/tcp
firewall-cmd --permanent --add-port=80/tcp
firewall-cmd --permanent --add-port=443/tcp

# RKE2 Server control plane and etcd
firewall-cmd --permanent --add-port=6443/tcp
firewall-cmd --permanent --add-port=9345/tcp
firewall-cmd --permanent --add-port=2379-2380/tcp

firewall-cmd --reload
```

### Step 2.4: Install Private Root CA

Copy your `root-ca.pem` certificate and update the system trust store:

```bash
cp root-ca.pem /etc/pki/ca-trust/source/anchors/
update-ca-trust extract
```

---

## 3. Install Single-Node RKE2 on the Registry Server

### Step 3.1: Create Required Directories

```bash
mkdir -p /etc/rancher/rke2
mkdir -p /var/lib/rancher/rke2/server/manifests
mkdir -p /var/lib/rancher/rke2/agent/images
mkdir -p /opt/rke2/artifacts
```

### Step 3.2: Copy Installation Artifacts

Copy the offline RKE2 installation archives into `/opt/rke2/artifacts/`:

```bash
cp /opt/rke2/artifacts/rke2-images*.tar.zst /var/lib/rancher/rke2/agent/images/
chmod +x /opt/rke2/artifacts/install.sh
```

### Step 3.3: Create Pod Security Admission Configuration

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
          - kube-system
          - cert-manager
          - local-path-provisioner
          - private-registry
        runtimeClasses: []
        usernames: []
EOF
```

### Step 3.4: Create RKE2 Server Configuration

Create `/etc/rancher/rke2/config.yaml`:

```bash
cat <<'EOF' > /etc/rancher/rke2/config.yaml
token: "changethistoarandomvalue"
cni: "cilium"
profile: "cis"
selinux: true
pod-security-admission-config-file: "/etc/rancher/rke2/rancher-psact.yaml"
tls-san:
  - "registry.infra.internal"
  - "192.168.98.5"
EOF
```

### Step 3.5: Run Installer and Start RKE2

```bash
INSTALL_RKE2_ARTIFACT_PATH="/opt/rke2/artifacts" \
INSTALL_RKE2_TYPE="server" \
INSTALL_RKE2_METHOD="tar" \
/opt/rke2/artifacts/install.sh

systemctl enable --now rke2-server
```

Wait until RKE2 finishes starting:

```bash
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
/var/lib/rancher/rke2/bin/kubectl get nodes -o wide
```

Add `kubectl` and `helm` to your system `PATH`:

```bash
ln -s /var/lib/rancher/rke2/bin/kubectl /usr/local/bin/kubectl
echo "export KUBECONFIG=/etc/rancher/rke2/rke2.yaml" >> ~/.bashrc
```

---

## 4. Install Local Path Provisioner

The SUSE Private Registry components (Harbor core, PostgreSQL, Redis, Trivy, and image storage) need persistent volumes.
We use Rancher `local-path-provisioner` to serve storage from the `/data` directory.

### Step 4.1: Create Namespace and Security Labels

`local-path-provisioner` requires access to host filesystems. Label the namespace as `privileged`:

```bash
kubectl create namespace local-path-provisioner
kubectl label namespace local-path-provisioner pod-security.kubernetes.io/enforce=privileged --overwrite
kubectl label namespace local-path-provisioner pod-security.kubernetes.io/enforce-version=latest --overwrite
kubectl label namespace local-path-provisioner pod-security.kubernetes.io/warn=privileged --overwrite
kubectl label namespace local-path-provisioner pod-security.kubernetes.io/warn-version=latest --overwrite
kubectl label namespace local-path-provisioner pod-security.kubernetes.io/audit=privileged --overwrite
kubectl label namespace local-path-provisioner pod-security.kubernetes.io/audit=latest --overwrite
```

### Step 4.2: Create Pull Secret (If pulling from dp.apps.rancher.io)

If you have connectivity to SUSE Application Collection during setup:

```bash
kubectl --namespace=local-path-provisioner create secret docker-registry application-collection \
  --docker-server=dp.apps.rancher.io \
  --docker-username="<APPCO_USERNAME>" \
  --docker-password="<APPCO_PASSWORD>"
```

### Step 4.3: Create Local Path Values File

Create `local-path-values.yaml`:

```yaml
cat <<'EOF' > local-path-values.yaml
global:
  imagePullSecrets:
    - application-collection
storageClass:
  create: true
  defaultClass: true
  pathPattern: "{{ .PVC.Namespace }}/{{ .PVC.Name }}/"
nodePathMap:
  - node: DEFAULT_PATH_FOR_NON_LISTED_NODES
    paths:
      - /data
EOF
```

### Step 4.4: Deploy Local Path Provisioner

```bash
# If using online OCI registry:
helm upgrade --install \
  --namespace local-path-provisioner \
  local-path-provisioner oci://dp.apps.rancher.io/charts/local-path-provisioner --version 0.0.37 \
  --values local-path-values.yaml

# Or if using local tar archive:
# helm upgrade --install \
#   --namespace local-path-provisioner \
#   local-path-provisioner ./local-path-provisioner-0.0.37.tgz \
#   --values local-path-values.yaml
```

Verify the storage class is ready and set to default:

```bash
kubectl get storageclass
```

Output:
```text
NAME                   PROVISIONER                     RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
local-path (default)   rancher.io/local-path           Delete          WaitForFirstConsumer   false                  1m
```

---

## 5. Install Cert-Manager

Install cert-manager to manage TLS certificates inside the cluster.

### Step 5.1: Create Namespace and Pull Secret

```bash
kubectl create namespace cert-manager

kubectl --namespace=cert-manager create secret docker-registry application-collection \
  --docker-server=dp.apps.rancher.io \
  --docker-username="<APPCO_USERNAME>" \
  --docker-password="<APPCO_PASSWORD>"
```

### Step 5.2: Create Cert-Manager Values File

Create `cert-manager-values.yaml`:

```yaml
cat <<'EOF' > cert-manager-values.yaml
global:
  imagePullSecrets:
    - application-collection
crds:
  enabled: true
EOF
```

### Step 5.3: Deploy Cert-Manager

```bash
# If using online OCI registry:
helm upgrade --install \
  --namespace cert-manager \
  cert-manager oci://dp.apps.rancher.io/charts/cert-manager --version 1.21.3 \
  --values cert-manager-values.yaml

# Or if using local tar archive:
# helm upgrade --install \
#   --namespace cert-manager \
#   cert-manager ./cert-manager-1.21.3.tgz \
#   --values cert-manager-values.yaml
```

Verify pods are running:

```bash
kubectl -n cert-manager get pods
```

---

## 6. Deploy SUSE Private Registry (Harbor)

### Step 6.1: Create Namespace

```bash
kubectl create namespace private-registry
```

### Step 6.2: Create Image Pull Secret for SUSE Registry

```bash
kubectl --namespace=private-registry create secret docker-registry suse-registry \
  --docker-server=registry.suse.com \
  --docker-username="<SUSE_REGISTRY_USERNAME>" \
  --docker-password="<SUSE_REGISTRY_PASSWORD>"
```

### Step 6.3: Create TLS and Root CA Secrets

1. Create the `tls-ca` secret containing your Root CA certificate:
   ```bash
   kubectl -n private-registry create secret generic tls-ca \
     --from-file=cacerts.pem=/etc/pki/ca-trust/source/anchors/root-ca.pem
   ```

2. Create the TLS server certificate secret for `registry.infra.internal`:
   ```bash
   kubectl -n private-registry create secret tls tls-registry \
     --cert=tls.crt \
     --key=tls.key
   ```

### Step 6.4: Create Private Registry Values File

Create `private-registry-values.yaml`:

```yaml
cat <<'EOF' > private-registry-values.yaml
global:
  imagePullSecrets:
    - suse-registry
expose:
  type: ingress
  ingress:
    className: traefik
    annotations:
      ingress.kubernetes.io/ssl-redirect: "true"
      ingress.kubernetes.io/proxy-body-size: "0"
    hosts:
      core: registry.infra.internal
  tls:
    certSource: secret
    secret:
      secretName: "tls-registry"
caSecretName: "tls-ca"
externalURL: https://registry.infra.internal
harborAdminPassword: "HarborSecurePassword123!"
persistence:
  registry:
    storageClass: local-path
    size: 150Gi
  jobservice:
    jobLog:
      storageClass: local-path
      size: 5Gi
  database:
    storageClass: local-path
    size: 10Gi
  redis:
    storageClass: local-path
    size: 10Gi
  trivy:
    storageClass: local-path
    size: 5Gi

core:
  quotaUpdateProvider: redis

database:
  maxOpenConns: 50
  maxIdleConns: 10
EOF
```

*(Note: Change `HarborSecurePassword123!` to your secure admin password).*

### Step 6.5: Deploy the Private Registry Helm Chart

```bash
# If using online OCI registry:
helm upgrade --install \
  --namespace private-registry \
  private-registry oci://registry.suse.com/private-registry/1.2/private-registry-helm \
  --values private-registry-values.yaml

# Or if using local tar archive:
# helm upgrade --install \
#   --namespace private-registry \
#   private-registry ./private-registry-helm-1.2.0.tgz \
#   --values private-registry-values.yaml
```

Wait for all pods in `private-registry` to become `Running`:

```bash
kubectl -n private-registry get pods -w
```

---

## 7. Verify Registry Access

1. Test connection to the registry web interface:
   ```bash
   curl -kI https://registry.infra.internal/
   ```

2. Log in with the Helm CLI or Docker/Crane:
   ```bash
   helm registry login registry.infra.internal -u admin -p "HarborSecurePassword123!"
   crane auth login registry.infra.internal -u admin -p "HarborSecurePassword123!"
   ```

3. Open your browser and navigate to:
   ```text
   https://registry.infra.internal
   ```
   Log in with username `admin` and your configured password.
   Create standard projects (e.g., `rancher`, `rancher/containers`, `dp.apps.rancher.io`, `registry.rancher.com`, `registry.suse.com`) with **Public** access enabled or configured robot accounts.
