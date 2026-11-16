# 2. Download Artifacts (Connected Host)

Complete this section on a computer with internet access.
You will download all files and container images.
Then, copy them to a USB drive or secure transfer media to bring into the air-gapped network.

---

## 1. Required Tools on the Connected Host

Install these tools on your internet-connected computer:

- `curl` (to download files)
- `helm` version 3 (to fetch charts)
- `crane` or `hauler` (to pull and push container images)

### Install Helm (if needed)

```bash
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

### Install Crane (if needed)

```bash
curl -sL "https://github.com/google/go-containerregistry/releases/latest/download/go-containerregistry_Linux_x86_64.tar.gz" | tar -xz crane
sudo mv crane /usr/local/bin/
```

### Install Hauler (if needed)

```bash
curl -sfL https://get.hauler.dev | bash
```

---

## 2. Download RKE2 Artifacts

Create a working directory for RKE2 version `v1.36.5+rke2r1`:

```bash
export RKE2_VERSION="v1.36.5+rke2r1"
export DOWNLOAD_DIR="$HOME/airgap-rke2/${RKE2_VERSION}"
mkdir -p "${DOWNLOAD_DIR}"
cd "${DOWNLOAD_DIR}"
```

### Download the RKE2 Installer Script

```bash
curl -sfL https://get.rke2.io -o install.sh
chmod +x install.sh
```

### Download the RKE2 Binaries and Images

Download the files from the SUSE Prime repository:

```bash
URL="https://prime.ribs.rancher.io/rke2/v1.36.5%2Brke2r1"

curl -fL "${URL}/rke2.linux-amd64.tar.gz" -o rke2.linux-amd64.tar.gz
curl -fL "${URL}/sha256sum-amd64.txt" -o sha256sum-amd64.txt
curl -fL "${URL}/rke2-images.linux-amd64.tar.zst" -o rke2-images.linux-amd64.tar.zst
curl -fL "${URL}/rke2-images-cilium.linux-amd64.tar.zst" -o rke2-images-cilium.linux-amd64.tar.zst
```

*(Note: You can also download them from GitHub release `https://github.com/rancher/rke2/releases/download/v1.36.5+rke2r1` if preferred).*

### Verify Checksums

Always verify the files before moving them into the secure zone:

```bash
sha256sum --check --ignore-missing sha256sum-amd64.txt
```

Expected output:
```text
rke2-images-cilium.linux-amd64.tar.zst: OK
rke2-images.linux-amd64.tar.zst: OK
rke2.linux-amd64.tar.gz: OK
```

---

## 3. Download Helm Charts

Create a directory for Helm charts:

```bash
mkdir -p "$HOME/airgap-charts"
cd "$HOME/airgap-charts"
```

### Download Cert-Manager Helm Chart (v1.21.3)

```bash
helm fetch oci://dp.apps.rancher.io/charts/cert-manager --version 1.21.3
```

This creates the file `cert-manager-1.21.3.tgz`.

### Download Local Path Provisioner Helm Chart (v0.0.37)

```bash
helm registry login dp.apps.rancher.io -u "$APPCO_USERNAME" --password-stdin <<< "$APPCO_PASSWORD"
helm fetch oci://dp.apps.rancher.io/charts/local-path-provisioner --version 0.0.37
```

This creates the file `local-path-provisioner-0.0.37.tgz`.

### Download SUSE Private Registry Helm Chart (v1.2)

```bash
helm registry login registry.suse.com -u "$SUSE_REGISTRY_USERNAME" --password-stdin <<< "$SUSE_REGISTRY_PASSWORD"
helm fetch oci://registry.suse.com/private-registry/1.2/private-registry-helm
```

This creates the file `private-registry-helm-1.2.0.tgz`.

### Download Rancher Prime Helm Chart (v2.15.3)

```bash
helm repo add rancher-prime https://charts.rancher.com/server-charts/prime
helm repo update rancher-prime
helm fetch rancher-prime/rancher --version 2.15.3
```

This creates the file `rancher-2.15.3.tgz`.

---

## 4. Download Container Images (Method A: Crane)

You can save container images into tar archives using `crane`.

### Step 4.1: Download Cert-Manager Images

```bash
mkdir -p "$HOME/airgap-images/cert-manager"
cd "$HOME/airgap-images/cert-manager"

CERT_IMAGES=$(helm template $HOME/airgap-charts/cert-manager-1.21.3.tgz | grep image: | awk -F "image:" '{ print $2 }' | tr -d ' "')

for IMG in $CERT_IMAGES; do
  NAME=$(basename "$IMG")
  echo "Pulling $IMG -> $NAME.tar"
  crane pull "$IMG" "$NAME.tar"
done
```

### Step 4.2: Download Rancher Prime Images

Download the official image list for Rancher v2.15.3:

```bash
mkdir -p "$HOME/airgap-images/rancher"
cd "$HOME/airgap-images/rancher"

curl -sL https://prime.ribs.rancher.io/rancher/v2.15.3/rancher-images.txt -o rancher-images-v2.15.3.txt
```

Download and save each image to a tar file:

```bash
SRC_REGISTRY="registry.rancher.com"

while read -r IMAGE; do
  [ -z "$IMAGE" ] && continue
  TAR_PATH="$HOME/airgap-images/rancher/files/${IMAGE}.tar"
  mkdir -p "$(dirname "$TAR_PATH")"
  
  if [ ! -f "$TAR_PATH" ]; then
    echo "Saving $IMAGE ..."
    crane pull "${SRC_REGISTRY}/${IMAGE}" "$TAR_PATH"
  else
    echo "Skipping $IMAGE, already exists"
  fi
done < rancher-images-v2.15.3.txt
```

---

## 5. Download Container Images and Charts (Method B: Hauler)

`hauler` downloads charts, images, and files into a single compressed store archive.

### Hauler Script

Save this script as `download-hauler.sh` on the connected machine:

```bash
#!/bin/bash
set -e

STORE_DIR="$HOME/hauler-store"
OUTPUT_DIR="$HOME/hauler-output"
mkdir -p "$STORE_DIR" "$OUTPUT_DIR"

RANCHER_VER="v2.15.3"
CERT_VER="1.21.3"
RKE2_VER="v1.36.5+rke2r1"

# 1. Add Cert-Manager chart and images
hauler --store "$STORE_DIR/bundle" store add chart cert-manager \
  --repo "oci://dp.apps.rancher.io/charts" \
  --version "$CERT_VER" \
  --add-images --platform linux/amd64

# 2. Add Rancher Prime chart
hauler --store "$STORE_DIR/bundle" store add chart rancher \
  --repo "https://charts.rancher.com/server-charts/prime" \
  --version "$RANCHER_VER" \
  --platform linux/amd64

# 3. Add Rancher images
curl -sL "https://prime.ribs.rancher.io/rancher/${RANCHER_VER}/rancher-images.txt" -o /tmp/rancher-images.txt
sed -i 's|^|registry.rancher.com/|' /tmp/rancher-images.txt
hauler --store "$STORE_DIR/bundle" store sync --image-txt /tmp/rancher-images.txt --platform linux/amd64

# 4. Save store to a single file
hauler --store "$STORE_DIR/bundle" store save --filename "$OUTPUT_DIR/rancher-airgap-bundle.tar.zst"
echo "Bundle created at: $OUTPUT_DIR/rancher-airgap-bundle.tar.zst"
```

Run the script:

```bash
chmod +x download-hauler.sh
./download-hauler.sh
```

---

## 6. Move Artifacts into the Air Gap

Transfer all downloaded directories to your internal media (USB drive or internal staging server):

- `install.sh`
- `rke2.linux-amd64.tar.gz`
- `sha256sum-amd64.txt`
- `rke2-images.linux-amd64.tar.zst`
- `rke2-images-cilium.linux-amd64.tar.zst`
- `cert-manager-1.21.3.tgz`
- `rancher-2.15.3.tgz`
- Image tar archives (or the Hauler bundle `.tar.zst`)
- RPM packages (`rke2-selinux`, `firewalld`, `iptables` if not in your internal mirror)

---

## 7. Push Images into the Private Registry

Inside the air-gapped network, log in to your internal registry and push images.
*(Note: If you have not deployed the internal registry yet, follow [3. Private Registry Deployment](03-private-registry-setup.md) first).*

### Method A: Push Images with Crane

On a host inside the network:

```bash
# Log in to private registry
crane auth login registry.infra.internal -u <USERNAME> -p <PASSWORD>

# Push cert-manager images
cd "$HOME/airgap-images/cert-manager"
for TAR in *.tar; do
  IMG_NAME="${TAR%.tar}"
  crane push "$TAR" "registry.infra.internal/rancher/containers/$IMG_NAME"
done

# Push Rancher images
cd "$HOME/airgap-images/rancher"
while read -r IMAGE; do
  [ -z "$IMAGE" ] && continue
  TAR_PATH="$HOME/airgap-images/rancher/files/${IMAGE}.tar"
  if [ -f "$TAR_PATH" ]; then
    echo "Pushing $IMAGE to registry.infra.internal ..."
    crane push "$TAR_PATH" "registry.infra.internal/${IMAGE}"
  fi
done < rancher-images-v2.15.3.txt
```

### Method B: Push Images with Hauler

If you used Hauler:

```bash
hauler --store "$HOME/hauler-store/bundle" store load --filename "$HOME/hauler-output/rancher-airgap-bundle.tar.zst"
hauler --store "$HOME/hauler-store/bundle" store copy registry://registry.infra.internal
```
