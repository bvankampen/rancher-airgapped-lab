#!/bin/sh


helm upgrade --install \
    --namespace local-path-provisioner --create-namespace \
    local-path-provisioner oci://dp.apps.rancher.io/charts/local-path-provisioner --version 0.0.37 \
    --values values.yaml
