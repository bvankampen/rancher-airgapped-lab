#!/bin/sh
CHART_VERSION="2.15.3"

helm get values rancher -n cattle-system -o yaml > values.yaml

helm upgrade \
  rancher oci://registry.lab.suse/rancher/rancher --version ${CHART_VERSION} \
  -n cattle-system \
  --values values.yaml

helm upgrade \
  rancher rancher-${CHART_VERSION}.tgz \
  -n cattle-system \
  --values values.yaml
