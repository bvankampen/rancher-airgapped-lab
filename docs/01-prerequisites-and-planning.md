# 1. Prerequisites and Planning

Before you start, make sure all servers and network settings are ready.

---

## 1. Hardware Requirements

Each RKE2 server node needs at least:

- **CPU:** 4 vCPUs or cores
- **Memory:** 16 GB RAM (minimum 8 GB for test setups; 16 GB+ recommended for production)
- **Disk:** 100 GB SSD or fast storage
- **Operating System:** Rocky Linux 9.x or Red Hat Enterprise Linux (RHEL) 9.x (64-bit x86_64)

The Load Balancer node needs:
- **CPU:** 2 vCPUs
- **Memory:** 4 GB RAM
- **Disk:** 40 GB storage

The Private Registry node (`registry.infra.internal`) needs:
- **CPU:** 4 vCPUs
- **Memory:** 16 GB RAM (minimum 8 GB)
- **Disk:** 200 GB+ SSD or dedicated storage partition mounted at `/data` for container images
- **Operating System:** Rocky Linux 9.x or RHEL 9.x (64-bit x86_64)

---

## 2. Server Inventory and IP Addresses

Assign static IP addresses and set DNS records for each host.

| Hostname | Role | Example IP | Notes |
| :--- | :--- | :--- | :--- |
| `lb-01` | Load Balancer | `192.168.98.10` | Runs HAProxy |
| `rke2-server-01` | RKE2 Server 1 | `192.168.98.11` | First node (cluster bootstrap) |
| `rke2-server-02` | RKE2 Server 2 | `192.168.98.12` | Second node (joins cluster) |
| `rke2-server-03` | RKE2 Server 3 | `192.168.98.13` | Third node (joins cluster) |
| `registry.infra.internal` | Local Registry | `192.168.98.5` | Stores container images |
| `repo.infra.internal` | Package Mirror | `192.168.98.6` | Stores RPM packages |

---

## 3. DNS Records

Add these DNS records to your internal DNS server:

```text
rancher.infra.internal    A    192.168.98.10   # Points to the Load Balancer
rke2-server-01            A    192.168.98.11   # Points to Node 1
rke2-server-02            A    192.168.98.12   # Points to Node 2
rke2-server-03            A    192.168.98.13   # Points to Node 3
registry.infra.internal   A    192.168.98.5    # Points to Private Registry
repo.infra.internal       A    192.168.98.6    # Points to Package Mirror
```

If you do not have a DNS server during early setup, add entries to `/etc/hosts` on all machines:

```bash
cat <<EOF >> /etc/hosts
192.168.98.10 rancher.infra.internal
192.168.98.11 rke2-server-01
192.168.98.12 rke2-server-02
192.168.98.13 rke2-server-03
192.168.98.5  registry.infra.internal
192.168.98.6  repo.infra.internal
EOF
```

---

## 4. Network and Firewall Port Requirements

The nodes must talk to each other over the local network.
Ensure no firewall blocks these ports between cluster nodes:

| Port / Protocol | Source | Destination | Purpose |
| :--- | :--- | :--- | :--- |
| **80/tcp** | Any / LB | All nodes | Ingress HTTP traffic (redirects to HTTPS) |
| **443/tcp** | Clients / LB | All nodes | Rancher UI and Ingress HTTPS |
| **6443/tcp** | Admin / Nodes | Server nodes | Kubernetes API Server |
| **9345/tcp** | Cluster nodes | Server nodes | RKE2 node join and supervisor API |
| **2379-2380/tcp** | Server nodes | Server nodes | etcd client and peer communication |
| **10250/tcp** | Server nodes | All nodes | Kubelet metrics and logs |
| **4240/tcp** | All nodes | All nodes | Cilium health check |
| **8472/udp** | All nodes | All nodes | Cilium VXLAN network overlay |
| **30000-32767/tcp** | Any / LB | All nodes | Kubernetes NodePort service range |
| **30000-32767/udp** | Any / LB | All nodes | Kubernetes NodePort service range |

### Cluster Internal Networks

Do not assign these IP ranges to physical network cards:

- **Pod Network (CIDR):** `10.42.0.0/16`
- **Service Network (CIDR):** `10.43.0.0/16`

---

## 5. Required Accounts and SSH Keys

1. You need `root` access (or full `sudo` rights) on every node.
2. Generate an SSH key on your admin jump host to connect easily:
   ```bash
   ssh-keygen -t ecdsa -b 384
   ssh-copy-id root@192.168.98.10   # lb-01
   ssh-copy-id root@192.168.98.11   # rke2-server-01
   ssh-copy-id root@192.168.98.12   # rke2-server-02
   ssh-copy-id root@192.168.98.13   # rke2-server-03
   ```

---

## 6. Certificates Needed

Prepare your certificate files before installation:

1. **Root CA Certificate:**
   - File name: `root-ca.pem`
   - Purpose: Added to the Linux system trust store so nodes trust the private registry and Rancher.
2. **Load Balancer and Rancher TLS Certificate and Key:**
   - File names: `fullchain.pem` (combined for HAProxy) or `tls.crt` and `tls.key` (for Kubernetes secret `tls-rancher-ingress`).
   - Contains: The server certificate for `rancher.infra.internal` and intermediate CA chain, plus the private key.
3. **Rancher CA Bundle:**
   - File name: `cacerts.pem`
   - Purpose: Stored inside the Kubernetes cluster in secret `tls-ca` for private CA verification.
4. **Private Registry TLS Certificate and Key:**
   - File names: `tls.crt` and `tls.key` (for Kubernetes secret `tls-registry-test` or `tls-registry`).
   - Contains: The server certificate for `registry.infra.internal` and intermediate CA chain, plus the private key.
