#!/bin/sh

kubectl create namespace local-path-provisioner
kubectl label namespace local-path-provisioner pod-security.kubernetes.io/enforce=privileged
kubectl label namespace local-path-provisioner pod-security.kubernetes.io/enforce-version=latest
kubectl label namespace local-path-provisioner pod-security.kubernetes.io/warn=privileged
kubectl label namespace local-path-provisioner pod-security.kubernetes.io/warn-version=latest
kubectl label namespace local-path-provisioner pod-security.kubernetes.io/audit=privileged
kubectl label namespace local-path-provisioner pod-security.kubernetes.io/audit=latest



helm upgrade --install \
    --namespace local-path-provisioner --create-namespace \
    local-path-provisioner oci://dp.apps.rancher.io/charts/local-path-provisioner --version 0.0.37 \
    --values values.yaml
