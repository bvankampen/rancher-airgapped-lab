#!/bin/sh

helm upgrade --install \
    --namespace cert-manager --create-namespace \
    cert-manager oci://dp.apps.rancher.io/charts/cert-manager --version 1.21.3 \
    --values values.yaml
