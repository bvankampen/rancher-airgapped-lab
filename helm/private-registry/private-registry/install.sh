#!/bin/sh

kubectl create namespace private-registry


kubectl -n private-registry create secret generic tls-ca \
  --from-file=cacerts.pem

kubectl -n private-registry create secret tls tls-registry-test \
    --cert=tls.crt \
    --key=tls.key

helm upgrade --install \
    --namespace private-registry --create-namespace \
    private-registry oci://registry.suse.com/private-registry/1.2/private-registry-helm \
    --values values.yaml
