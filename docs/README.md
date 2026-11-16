# Air-Gapped Rancher Prime and RKE2 Installation Guide

This guide explains how to install RKE2 and SUSE Rancher Prime by hand in an air-gapped environment.
An air-gapped network has no connection to the internet.
All files and container images must be downloaded outside and moved inside manually.

---

## Architecture Overview

```
                      +-----------------------------+
                      |   HAProxy Load Balancer     |
                      |   rancher.infra.internal    |
                      |   IP: 192.168.98.10 (example)|
                      +--------------+--------------+
                                     |
              +----------------------+----------------------+
              |                      |                      |
              v                      v                      v
     +-----------------+    +-----------------+    +-----------------+
     |  RKE2 Node 1    |    |  RKE2 Node 2    |    |  RKE2 Node 3    |
     |  192.168.98.11  |    |  192.168.98.12  |    |  192.168.98.13  |
     |  (Initial Node) |    |  (Join Node)    |    |  (Join Node)    |
     +-----------------+    +-----------------+    +-----------------+
              \                      |                      /
               +---------------------+---------------------+
                                     |
                      +--------------v--------------+
                      |  Private Container Registry |
                      |    registry.infra.internal  |
                      +-----------------------------+
```

### Components and Versions

| Component | Version | Purpose |
| :--- | :--- | :--- |
| **Operating System** | Rocky Linux 9 / RHEL 9 | Host operating system |
| **Kubernetes Engine** | RKE2 `v1.36.5+rke2r1` | Secure Kubernetes runtime |
| **Network Plugin (CNI)** | Cilium | Cluster networking and security |
| **Cluster Hardening** | CIS Profile (`cis`) | Security benchmarks and restricted PSA |
| **Cert-Manager** | `v1.21.3` | Certificate management inside cluster |
| **Rancher Prime** | `v2.15.3` | Kubernetes management platform |
| **Load Balancer** | HAProxy | TLS termination and traffic routing |
| **Container Registry** | SUSE Private Registry 1.2 (Harbor) | Air-gapped image storage and distribution |

---

## Documentation Structure

Follow the steps in this order:

- **[1. Prerequisites and Planning](01-prerequisites-and-planning.md)**  
  Review hardware, network ports, firewall requirements, and DNS names.

- **[2. Download Artifacts (Connected Host)](02-download-artifacts.md)**  
  Download all files, RPMs, Helm charts, and container images before entering the air gap.

- **[3. Private Registry Deployment (SUSE Private Registry)](03-private-registry-setup.md)**  
  Deploy SUSE Private Registry (Harbor), Local Path Provisioner, and cert-manager on RKE2.

- **[4. Load Balancer Setup (HAProxy)](04-load-balancer-setup.md)**  
  Configure HAProxy in TCP mode with HTTPS health checks to distribute traffic to the nodes.

- **[5. Node Operating System Preparation](05-node-preparation.md)**  
  Configure repos, firewall rules, CIS sysctl settings, etcd user, and private Root CA.

- **[6. RKE2 Air-Gapped Cluster Installation](06-rke2-cluster-install.md)**  
  Install the 3-node RKE2 cluster with PSACT hardening, registry mirroring, and Cilium configuration.

- **[7. Cert-Manager Installation](07-cert-manager-install.md)**  
  Deploy cert-manager from local images and charts.

- **[8. Rancher Prime Installation](08-rancher-install.md)**  
  Deploy Rancher Prime using Helm with custom CA certificates and private registry.

- **[9. Operations, Backup, and Troubleshooting](09-backup-and-troubleshooting.md)**  
  Check cluster health, view logs, restart services, and troubleshoot common errors.

- **[10. Downstream RKE2 Cluster Provisioning](10-downstream-cluster.md)**  
  Prepare downstream nodes and provision a hardened RKE2 workload cluster from Rancher.

---

## Exporting Documentation to PDF

You can compile all documentation into a single PDF file using the script in the repository root:

```bash
./generate-pdf.sh
```

This generates `rancher-prime-airgap-installation-guide.pdf`.

