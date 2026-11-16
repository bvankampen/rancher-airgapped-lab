#!/bin/sh

CHART_VERSION="2.15.3"
CERT_MANAGER_VERSION=1.21.3

helm upgrade --install \
  cert-manager oci://registry.lab.suse/rancher/hauler/cert-manager --version ${CERT_MANAGER_VERSION} \
  -n cert-manager --create-namespace \
  --set global.imageRegistry=registry.lab.suse/rancher \
  --set crds.enabled=true

kubectl create namespace cattle-system
kubectl -n cattle-system create secret tls tls-rancher-ingress \
  --cert=tls.crt \
  --key=tls.key
kubectl -n cattle-system create secret generic tls-ca \
  --from-file=cacerts.pem

helm install \
  rancher oci://registry.lab.suse/rancher/rancher --version ${CHART_VERSION} \
  -n cattle-system \
  --values values.yaml

helm install \
  rancher rancher-${CHART_VERSION}.tgz \
  -n cattle-system \
  --values values.yaml
