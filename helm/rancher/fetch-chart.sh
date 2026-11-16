#!/bin/bash
set -euo pipefail

CHART_VERSION="2.15.3"
REPO_URL="https://charts.rancher.com/server-charts/prime"

echo "Adding Rancher Prime Helm repository..."
helm repo add rancher-prime "$REPO_URL"
helm repo update rancher-prime

helm fetch rancher-prime/rancher --version "${CHART_VERSION}"
