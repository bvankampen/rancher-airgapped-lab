# 9. Operations, Backup, and Troubleshooting

This document covers day-to-day operations, etcd backups, and fixes for common issues.

---

## 1. Checking Cluster and Service Health

### Check Node and Pod Status

Run these commands from any node or your admin machine:

```bash
# Check node status
kubectl get nodes -o wide

# Check all pods in all namespaces
kubectl get pods -A

# Check pods with problems (not Running or Completed)
kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded
```

### Check the RKE2 Service

On any RKE2 server node:

```bash
# Check service status
systemctl status rke2-server

# View live system logs
journalctl -u rke2-server -f

# View the last 100 log lines
journalctl -u rke2-server --no-pager -n 100
```

---

## 2. Using crictl to Inspect Containers Directly

RKE2 uses containerd. You can check containers even if `kubectl` is not working.

Set the socket path:

```bash
export CONTAINER_RUNTIME_ENDPOINT=unix:///run/k3s/containerd/containerd.sock
```

Useful commands:

```bash
# List all running pods
crictl pods

# List all containers
crictl ps

# View container logs
crictl logs <CONTAINER_ID>

# List all container images on the node
crictl images
```

---

## 3. etcd Backups and Restores

RKE2 saves etcd snapshots automatically every 12 hours.

### Take a Manual Backup

Run this on any server node:

```bash
rke2 etcd-snapshot save --name manual-backup
```

### List Existing Snapshots

```bash
rke2 etcd-snapshot list
```

Snapshots are saved under:
```text
/var/lib/rancher/rke2/server/db/snapshots/
```
Copy these files to an external safe location on a regular schedule.

---

## 4. Certificate Management

RKE2 certificates are valid for 12 months and renew automatically upon restart.

### Check Certificate Expiration

```bash
rke2 certificate check
```

### Manually Rotate Certificates

If certificates must be rotated early:

1. Stop RKE2 server:
   ```bash
   systemctl stop rke2-server
   ```
2. Rotate certificates:
   ```bash
   rke2 certificate rotate
   ```
3. Start RKE2 server:
   ```bash
   systemctl start rke2-server
   ```

---

## 5. Troubleshooting Common Problems

### Problem 1: Pods Stuck in `ImagePullBackOff` or `ErrImagePull`

**Cause:** The pod cannot pull an image from `registry.infra.internal`.

**Fix:**
1. Check which image failed:
   ```bash
   kubectl describe pod <POD_NAME> -n <NAMESPACE>
   ```
2. Check if the image exists in `registry.infra.internal`:
   ```bash
   curl -I https://registry.infra.internal/v2/<IMAGE_NAME>/tags/list
   ```
3. If missing, copy and push the image into the registry using the steps in [2. Download Artifacts](02-download-artifacts.md).
4. Verify the node trusts the registry certificate in `/etc/pki/ca-trust/source/anchors/`.

---

### Problem 2: HAProxy Shows Backends DOWN

**Cause:** HAProxy health check cannot reach the node on port 443.

**Fix:**
1. Log in to the node that is reported DOWN.
2. Test the `/healthz` endpoint locally:
   ```bash
   curl -k -H "Host: rancher.infra.internal" https://127.0.0.1:443/healthz
   ```
   Expected response: `ok` (HTTP 200).
3. If curl fails, check if the Ingress controller is running:
   ```bash
   kubectl get pods -n kube-system -l app.kubernetes.io/name=rke2-ingress-nginx
   ```
4. Check firewalld on the node:
   ```bash
   firewall-cmd --list-ports
   ```
   Ensure port `443/tcp` is open.

---

### Problem 3: Second or Third Node Cannot Join the Cluster

**Cause:** The new node cannot talk to Node 1 on port 9345 or the secret token is wrong.

**Fix:**
1. Test network connectivity from the new node to Node 1:
   ```bash
   curl -k https://192.168.98.11:9345/ping
   ```
   Expected response: `pong`.
2. Check firewalld on Node 1: ensure `9345/tcp` and `6443/tcp` are allowed.
3. Compare the `token:` in `/etc/rancher/rke2/config.yaml` on Node 2 with Node 1. They must match exactly.
4. Check node logs:
   ```bash
   journalctl -u rke2-server -n 100 --no-pager
   ```

---

### Problem 4: Pod Security Admission (PSA) Violations

**Cause:** The cluster runs in `cis` profile with restricted Pod Security.
Pods that run as root or need host ports are blocked unless their namespace is exempt.

**Fix:**
1. Verify `/etc/rancher/rke2/rancher-psact.yaml` contains exemptions for required namespaces:
   - `cattle-fleet-local-system`
   - `cattle-fleet-system`
   - `cattle-scc-system`
   - `cattle-system`
   - `kube-system`
2. If adding new workloads that need elevated privileges, create a namespace label:
   ```bash
   kubectl label namespace <MY_NAMESPACE> 'pod-security.kubernetes.io/enforce=privileged'
   ```

---

## 6. How to Reboot a Cluster Node Safely

If you need to reboot a node (e.g., after OS updates):

1. Drain the node gracefully from another node:
   ```bash
   kubectl drain <NODE_NAME> --ignore-daemonsets --delete-emptydir-data
   ```
2. Stop RKE2 service on the node:
   ```bash
   systemctl stop rke2-server
   ```
3. Reboot the host:
   ```bash
   reboot
   ```
4. After the node boots up, check RKE2:
   ```bash
   systemctl status rke2-server
   ```
5. Uncordon the node so pods can schedule again:
   ```bash
   kubectl uncordon <NODE_NAME>
   ```
6. Always reboot nodes **one at a time**. Keep at least two servers online so etcd maintains quorum.
