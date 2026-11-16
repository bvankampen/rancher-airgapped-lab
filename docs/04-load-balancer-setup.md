# 4. Load Balancer Setup (HAProxy)

This section explains how to set up the HAProxy load balancer.
The load balancer sits in front of the three RKE2 nodes.
It accepts HTTPS traffic from users and sends it to the nodes.

---

## 1. Install HAProxy

Log in to the load balancer machine (example IP: `192.168.98.10`).
Install the HAProxy package:

```bash
sudo dnf install -y haproxy
```

---

## 2. Understand TLS and Health Checks in TCP Mode

In TCP mode:
- **Layer 4 Passthrough:** HAProxy forwards raw TLS traffic on port 443 directly to the three RKE2 nodes.
- **TLS Termination:** The TLS certificate (`tls.crt` / `tls.key`) is managed inside the Kubernetes cluster by the RKE2 Ingress controller in the `tls-rancher-ingress` secret (see Chapter 8).
- **HTTPS Health Checking:** HAProxy probes each backend node using HTTPS (`GET /healthz`) with SNI set to `rancher.infra.internal` to ensure each node is healthy before routing traffic to it.

---

## 3. Configure HAProxy

Open `/etc/haproxy/haproxy.cfg`:

```bash
sudo vi /etc/haproxy/haproxy.cfg
```

Add the following configuration:

```haproxy
global
    log /dev/log    local0
    log /dev/log    local1 notice
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin
    stats timeout 30s
    user haproxy
    group haproxy
    daemon

    # Default SSL material locations
    ca-base /etc/ssl/certs
    crt-base /etc/ssl/private

    # Mozilla Intermediate SSL profile
    ssl-default-bind-ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384
    ssl-default-bind-ciphersuites TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256
    ssl-default-bind-options ssl-min-ver TLSv1.2 no-tls-tickets

defaults
    log     global
    mode    http
    option  httplog
    option  dontlognull
    option  forwardfor
    timeout connect 5000
    timeout client  50000
    timeout server  50000
    timeout tunnel  3600s

# HAProxy statistics web page
listen stats
    bind 0.0.0.0:8080
    stats enable
    stats uri     /
    stats refresh 5s

# Frontend HTTP: redirects all port 80 traffic to port 443
frontend rancher-http
    bind 0.0.0.0:80
    mode http
    http-request redirect scheme https code 301

# Frontend HTTPS: TCP passthrough to backend RKE2 nodes
frontend rancher-443
    bind 0.0.0.0:443
    mode tcp
    option tcplog
    default_backend be-rancher-443

# Backend: forwards TCP traffic to the three RKE2 nodes with HTTPS health checks
backend be-rancher-443
    mode tcp
    balance roundrobin
    option httpchk GET /healthz
    http-check send hdr Host rancher.infra.internal
    http-check expect status 200
    server rke2-server-01 192.168.98.11:443 check check-ssl ssl verify none sni str(rancher.infra.internal)
    server rke2-server-02 192.168.98.12:443 check check-ssl ssl verify none sni str(rancher.infra.internal)
    server rke2-server-03 192.168.98.13:443 check check-ssl ssl verify none sni str(rancher.infra.internal)
```

---

## 4. (Optional) RKE2 Kubernetes API Load Balancing

If you also want high availability for `kubectl` (port 6443) and node join requests (port 9345), add TCP mode frontends to `/etc/haproxy/haproxy.cfg`:

```haproxy
frontend rke2-api-6443
    bind 0.0.0.0:6443
    mode tcp
    default_backend be-rke2-api-6443

backend be-rke2-api-6443
    mode tcp
    balance roundrobin
    server rke2-server-01 192.168.98.11:6443 check
    server rke2-server-02 192.168.98.12:6443 check
    server rke2-server-03 192.168.98.13:6443 check

frontend rke2-supervisor-9345
    bind 0.0.0.0:9345
    mode tcp
    default_backend be-rke2-supervisor-9345

backend be-rke2-supervisor-9345
    mode tcp
    balance roundrobin
    server rke2-server-01 192.168.98.11:9345 check
    server rke2-server-02 192.168.98.12:9345 check
    server rke2-server-03 192.168.98.13:9345 check
```

---

## 5. Configure Firewall on Load Balancer

Open the required ports:

```bash
sudo firewall-cmd --permanent --add-port=80/tcp
sudo firewall-cmd --permanent --add-port=443/tcp
sudo firewall-cmd --permanent --add-port=8080/tcp
sudo firewall-cmd --reload
```

---

## 6. Start and Enable HAProxy

1. Test configuration syntax:
   ```bash
   sudo haproxy -c -f /etc/haproxy/haproxy.cfg
   ```
   Output must show: `Configuration file is valid`.

2. Enable and start the systemd service:
   ```bash
   sudo systemctl enable --now haproxy
   ```

3. Check service status:
   ```bash
   sudo systemctl status haproxy
   ```

4. View the status page in a browser:
   ```text
   http://192.168.98.10:8080/
   ```
   *(Note: Backends will show DOWN until RKE2 and Rancher are installed in later steps).*
