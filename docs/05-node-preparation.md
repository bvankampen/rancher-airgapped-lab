# 5. Node Operating System Preparation

Run all the steps in this file on **every RKE2 node** (`rke2-server-01`, `rke2-server-02`, and `rke2-server-03`).
Log in as `root` (or use `sudo -i`).

---

## 1. Disable Swap

Kubernetes requires swap memory to be turned off.

1. Turn off active swap immediately:
   ```bash
   swapoff -a
   ```

2. Stop the systemd swap service:
   ```bash
   systemctl stop swap.target
   systemctl mask swap.target
   ```

3. Disable swap in `/etc/fstab` so it does not turn on after reboot:
   ```bash
   sed -i '/swap/s/^\(.*\)$/#\1/g' /etc/fstab
   ```

---

## 2. Configure Local Package Repositories

In an air-gapped network, disable public internet repositories and use your local package mirror.

1. Disable all existing public repositories:
   ```bash
   for f in /etc/yum.repos.d/*.repo; do
     sed -i 's/^enabled=1/enabled=0/' "$f"
   done
   ```

2. Create a new repository file pointing to your internal mirror (example: `repo.infra.internal`):
   ```bash
   cat <<'EOF' > /etc/yum.repos.d/local-mirror.repo
   [rocky-9.8-baseos]
   name=Rocky Linux 9.8 - BaseOS (Internal Mirror)
   baseurl=https://repo.infra.internal/repo/pub/rocky/9.8/BaseOS/x86_64/os/
   enabled=1
   gpgcheck=0

   [rocky-9.8-appstream]
   name=Rocky Linux 9.8 - AppStream (Internal Mirror)
   baseurl=https://repo.infra.internal/repo/pub/rocky/9.8/AppStream/x86_64/os/
   enabled=1
   gpgcheck=0

   [rocky-9.8-extras]
   name=Rocky Linux 9.8 - Extras (Internal Mirror)
   baseurl=https://repo.infra.internal/repo/pub/rocky/9.8/extras/x86_64/os/
   enabled=1
   gpgcheck=0

   [rhel-9-selinux]
   name=Redhat Enterprise Linux 9 - RKE2 SELINUX
   baseurl=https://repo.infra.internal/repo/rke2/latest/common/centos/9/noarch/
   enabled=1
   gpgcheck=0
   EOF
   ```

3. Clean and refresh repository metadata:
   ```bash
   dnf clean all
   dnf makecache
   ```

---

## 3. Install Required Packages

Install `firewalld`, `iptables`, and the `rke2-selinux` policy package:

```bash
dnf install -y firewalld iptables rke2-selinux
```

---

## 4. Install Private Root CA Certificate

The nodes must trust your internal Certificate Authority (CA) to connect to the internal registry and web services.

1. Copy your root CA file to the anchors folder:
   ```bash
   mkdir -p /etc/pki/ca-trust/source/anchors
   cp root-ca.pem /etc/pki/ca-trust/source/anchors/root-ca.pem
   chmod 644 /etc/pki/ca-trust/source/anchors/root-ca.pem
   ```

2. Update the system certificate trust store:
   ```bash
   update-ca-trust extract
   ```

3. Verify that the node trusts the internal registry:
   ```bash
   curl -I https://registry.infra.internal
   ```
   *(It must not show certificate verification errors).*

---

## 5. Configure the Firewall (Firewalld)

1. Start and enable `firewalld`:
   ```bash
   systemctl enable --now firewalld
   ```

2. Enable masquerading on the public zone:
   ```bash
   firewall-cmd --permanent --zone=public --add-masquerade
   ```

3. Allow Pod and Service internal networks in the trusted zone:
   ```bash
   firewall-cmd --permanent --zone=trusted --add-source=10.42.0.0/16
   firewall-cmd --permanent --zone=trusted --add-source=10.43.0.0/16
   ```

4. Open the required ports for RKE2, Cilium, and Ingress:
   ```bash
   # Ingress and web traffic
   firewall-cmd --permanent --add-port=80/tcp
   firewall-cmd --permanent --add-port=443/tcp

   # Kubernetes API and RKE2 Supervisor
   firewall-cmd --permanent --add-port=6443/tcp
   firewall-cmd --permanent --add-port=9345/tcp

   # etcd database
   firewall-cmd --permanent --add-port=2379-2380/tcp

   # Kubelet metrics
   firewall-cmd --permanent --add-port=10250/tcp

   # Cilium CNI network overlay and health checks
   firewall-cmd --permanent --add-port=8472/udp
   firewall-cmd --permanent --add-port=4240/tcp

   # NodePort range
   firewall-cmd --permanent --add-port=30000-32767/tcp
   firewall-cmd --permanent --add-port=30000-32767/udp
   ```

5. Reload the firewall to apply all rules:
   ```bash
   firewall-cmd --reload
   ```

6. Verify the active ports:
   ```bash
   firewall-cmd --list-all
   ```

---

## 6. Apply CIS Benchmark Hardening

The RKE2 `cis` security profile requires kernel settings and an `etcd` system user.

### Step 6.1: Create etcd System User and Directory

```bash
# Create etcd group and user
groupadd --system etcd
useradd --system -g etcd -s /sbin/nologin -M -c "etcd user" etcd

# Create etcd database directory with secure permissions
mkdir -p /var/lib/rancher/rke2/server/db/etcd
chown -R etcd:etcd /var/lib/rancher/rke2/server/db/etcd
chmod 700 /var/lib/rancher/rke2/server/db/etcd
```

### Step 6.2: Create CIS sysctl Configuration

Create the file `/etc/sysctl.d/60-rke2-cis.conf`:

```bash
cat <<'EOF' > /etc/sysctl.d/60-rke2-cis.conf
# RKE2 CIS sysctl configuration
vm.panic_on_oom=0
vm.overcommit_memory=1
kernel.panic=10
kernel.panic_on_oops=1
net.ipv4.conf.all.forwarding=1
net.ipv6.conf.all.forwarding=1
EOF
```

Apply the new settings immediately:

```bash
sysctl --system
```

---

## 7. Set Shell Environment and Helpful Aliases

Add paths and `kubectl` completion to `/root/.bashrc`:

```bash
cat <<'EOF' >> /root/.bashrc

# RKE2 and Kubectl configuration
export PATH=$PATH:/var/lib/rancher/rke2/bin
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
export CONTAINER_RUNTIME_ENDPOINT=unix:///run/k3s/containerd/containerd.sock
export CONTAINERD_ADDRESS=/run/k3s/containerd/containerd.sock
export CONTAINERD_NAMESPACE=k8s.io

# Handy aliases and bash completion
alias k=kubectl
source <(/var/lib/rancher/rke2/bin/kubectl completion bash 2>/dev/null)
complete -o default -F __start_kubectl k 2>/dev/null
EOF
```

Source the file in your current session:

```bash
source /root/.bashrc
```
