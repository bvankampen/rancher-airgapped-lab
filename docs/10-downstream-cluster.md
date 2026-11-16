# 10. Downstream RKE2 Cluster Provisioning

After Rancher Prime is running, you can create downstream RKE2 workload clusters.
This guide explains how to prepare the downstream nodes and deploy a hardened, air-gapped RKE2 cluster using a Kubernetes manifest.

---

## 1. Prepare Downstream Nodes

Run the node preparation steps from [5. Node Operating System Preparation](05-node-preparation.md) on every downstream node before joining the cluster:

1. Disable swap.
2. Configure the internal package mirror (`repo.infra.internal`) and install `firewalld`, `iptables`, and `rke2-selinux`.
3. Install your private Root CA (`root-ca.pem`) into `/etc/pki/ca-trust/source/anchors/` and run `update-ca-trust extract`.
4. Configure `firewalld`:
   - On **all downstream nodes** (control plane and workers), open `8472/udp`, `4240/tcp`, `10250/tcp`, `80/tcp`, `443/tcp`, `30000-32767/tcp`, and `30000-32767/udp`, and allow `10.42.0.0/16` and `10.43.0.0/16` in the `trusted` zone.
   - On **control-plane nodes** only, also open `6443/tcp`, `9345/tcp`, and `2379-2380/tcp`.
5. Apply CIS hardening:
   - Create `/etc/sysctl.d/60-rke2-cis.conf` on **all downstream nodes** and run `sysctl --system`.
   - Create the `etcd` user, `etcd` group, and `/var/lib/rancher/rke2/server/db/etcd` directory on **control-plane nodes**.

---

## 2. Create the Cluster Manifest

You can define a downstream RKE2 cluster declaratively using a `Cluster` manifest (see `downstream/cluster.yaml` in this repository).

### Step 2.1: Encode Your Root CA Certificate

Rancher needs your private Root CA certificate in Base64 format for the registry configuration.
Run this command on a host that has `root-ca.pem`:

```bash
base64 -w 0 /etc/pki/ca-trust/source/anchors/root-ca.pem
```

Copy the single-line output string for the `caBundle` field below.

### Step 2.2: Create cluster.yaml

Create `cluster.yaml` on your admin workstation or jump host (replace `<BASE64_ROOT_CA>` with the string from Step 2.1):

```yaml
cat <<'EOF' > cluster.yaml
apiVersion: provisioning.cattle.io/v1
kind: Cluster
metadata:
  name: prod-cluster
  namespace: fleet-default
spec:
  defaultPodSecurityAdmissionConfigurationTemplateName: rancher-restricted
  kubernetesVersion: v1.36.5+rke2r1
  localClusterAuthEndpoint:
    enabled: false
  rkeConfig:
    chartValues:
      rke2-cilium: {}
      rke2-ingress-nginx: {}
      rke2-traefik: {}
    dataDirectories:
      k8sDistro: ""
      provisioning: ""
      systemAgent: ""
    etcd:
      disableSnapshots: false
      snapshotRetention: 5
      snapshotScheduleCron: "0 */5 * * *"
    machineGlobalConfig:
      cni: cilium
      disable-kube-proxy: false
      etcd-expose-metrics: false
      ingress-controller: traefik
      selinux: true
    machineSelectorConfig:
      - config:
          profile: cis
          protect-kernel-defaults: true
    registries:
      configs:
        registry.infra.internal:
          caBundle: "<BASE64_ROOT_CA>"
      mirrors:
        dp.apps.rancher.io:
          endpoint:
            - https://registry.infra.internal
          rewrite:
            (.*): dp.apps.rancher.io/$1
        registry.rancher.com:
          endpoint:
            - https://registry.infra.internal
          rewrite:
            (.*): registry.rancher.com/$1
        registry.suse.com:
          endpoint:
            - https://registry.infra.internal
          rewrite:
            (.*): registry.suse.com/$1
    upgradeStrategy:
      controlPlaneConcurrency: "1"
      controlPlaneDrainOptions:
        deleteEmptyDirData: true
        disableEviction: false
        enabled: false
        force: false
        gracePeriod: -1
        ignoreDaemonSets: true
        skipWaitForDeleteTimeoutSeconds: 0
        timeout: 120
      workerConcurrency: "1"
      workerDrainOptions:
        deleteEmptyDirData: true
        disableEviction: false
        enabled: false
        force: false
        gracePeriod: -1
        ignoreDaemonSets: true
        skipWaitForDeleteTimeoutSeconds: 0
        timeout: 120
EOF
```

### Key Settings Explained

- **`defaultPodSecurityAdmissionConfigurationTemplateName: rancher-restricted`:** Enforces restricted Pod Security Admission across the downstream cluster.
- **`kubernetesVersion: v1.36.5+rke2r1`:** Matches the RKE2 version staged in your private registry.
- **`machineGlobalConfig`:** Enables `cilium` CNI, `traefik` ingress controller, and `selinux: true`.
- **`machineSelectorConfig`:** Applies `profile: cis` and `protect-kernel-defaults: true` to all nodes.
- **`registries`:** Routes all image pulls to `registry.infra.internal` using your private CA bundle.
- **`etcd`:** Takes automatic etcd snapshots every 5 hours and keeps the last 5 snapshots.

---

## 3. Apply the Cluster Manifest

Apply `cluster.yaml` to the **Rancher management cluster** (not the downstream nodes):

```bash
kubectl apply -f cluster.yaml
```

Verify that Rancher created the cluster object:

```bash
kubectl -n fleet-default get clusters.provisioning.cattle.io
```

---

## 4. Register Downstream Nodes

1. Open the Rancher Web UI at `https://rancher.infra.internal`.
2. Go to **Cluster Management** and click `prod-cluster`.
3. Open the **Registration** tab.
4. For your **control-plane nodes**:
   - Check **etcd** and **Control Plane** (uncheck **Worker**).
   - Copy the registration command and run it as `root` on each control-plane node one by one.
5. For your **worker nodes**:
   - Check **Worker** only (uncheck **etcd** and **Control Plane**).
   - Copy the registration command and run it as `root` on each worker node.

*(Note: If you use a private CA, ensure the registration command includes `--ca-checksum` or that `root-ca.pem` is already trusted on every node).*

---

## 5. Verify the Downstream Cluster

1. Check the cluster status on the Rancher management cluster:
   ```bash
   kubectl -n fleet-default get clusters.provisioning.cattle.io prod-cluster
   ```
   Wait until `READY` shows `True`.

2. In the Rancher Web UI, confirm `prod-cluster` shows state **Active** and all control-plane and worker nodes show **Active**.
3. Download the downstream cluster `kubeconfig` from the Rancher UI and verify node readiness:
   ```bash
   kubectl --kubeconfig=./prod-cluster.yaml get nodes -o wide
   ```
