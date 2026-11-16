#!/bin/bash

STORE_DIR=$HOME/tmp/hauler
OUTPUT_DIR=$HOME/tmp/hauler-output
EXTRACT_DIR=$HOME/tmp/hauler-extract

RANCHER_VERSION=v2.15.3
RANCHER_REGISTRY=registry.rancher.com
RANCHER_IMAGES_LIST="https://prime.ribs.rancher.io/rancher/$RANCHER_VERSION/rancher-images.txt"

RKE2_VERSION=v1.36.5+rke2r1
RKE2_VERSION_URL=${RKE2_VERSION/+/%2B}
RKE2_SOURCE="https://prime.ribs.rancher.io/rke2"

LOCAL_REGISTRY="registry.lab.suse"
LOCAL_REGISTRY_RANCHER_PROJECT=""

# Charts to download (including images)
# <name>;<repo>;<version>;<local_registry_project;
declare -a CHARTS=(
  "cert-manager;oci://dp.apps.rancher.io/charts;1.21.3;rancher"
  "neuvector;https://charts.rancher.io/;110.0.4+up2.11.4;"
  "rancher-backup-crd;https://charts.rancher.io;110.0.3+up11.0.4;"
  "rancher-backup;https://charts.rancher.io;110.0.3+up11.0.4;"
  "rancher-compliance;https://charts.rancher.io;110.3.0+up1.5.4;"
  "rancher-logging;https://charts.rancher.io;110.0.0+up4.10.0-rancher.24;"
  "rancher-monitoring-dashboards;https://charts.rancher.io;110.0.1+up0.1.4"
  "prometheus-operator;oci://dp.apps.rancher.io/charts;92.14.1;rancher"
  )

# RKE2 artifacts to download
declare -a RKE2_FILES=(
  "rke2-images.linux-amd64.tar.zst"
  "rke2-images-cilium.linux-amd64.tar.zst"
  "rke2.linux-amd64.tar.gz"
  "sha256sum-amd64.txt"
)

mkdir -p ${STORE_DIR}
mkdir -p ${OUTPUT_DIR}

get_charts() {
  for CHART in "${CHARTS[@]}"; do
    IFS=";" read -r CHART_NAME CHART_REPO CHART_VERSION CHART_LOCAL_REPO <<< "${CHART}"
    hauler --store "${STORE_DIR}/${CHART_NAME}-${CHART_VERSION}" store \
      add chart "${CHART_NAME}" \
      --repo "${CHART_REPO}" \
      --version "${CHART_VERSION}" \
      --add-images \
      --add-dependencies \
      --platform linux/amd64

    hauler --store ${STORE_DIR}/${CHART_NAME}-${CHART_VERSION} \
      store save --filename ${OUTPUT_DIR}/chart-${CHART_NAME}-${CHART_VERSION}.tar.zst

  done
}

get_rancher_artifacts() {
  NAME=rancher-${RANCHER_VERSION}

  RANCHER_IMAGES_LIST_FILE="${OUTPUT_DIR}/rancher-images-${RANCHER_VERSION}.txt"

  hauler --store "${STORE_DIR}/${NAME}" store \
    add chart "rancher" \
    --repo "https://charts.rancher.com/server-charts/prime" \
    --version "${RANCHER_VERSION}" \
    --add-dependencies \
    --platform linux/amd64

  curl -s -L ${RANCHER_IMAGES_LIST} -o ${RANCHER_IMAGES_LIST_FILE}
  sed -i "s/^/${RANCHER_REGISTRY}\//" ${RANCHER_IMAGES_LIST_FILE}

  hauler --store "${STORE_DIR}/${NAME}" store \
    sync \
    --image-txt ${RANCHER_IMAGES_LIST_FILE} \
    --platform linux/amd64 \
    --concurrency 10

  hauler --store ${STORE_DIR}/${NAME} \
    store save --filename ${OUTPUT_DIR}/${NAME}.tar.zst

  rm ${RANCHER_IMAGES_LIST_FILE}
}

get_rke2_artifacts() {
  NAME=rke2-${RKE2_VERSION}

  hauler --store ${STORE_DIR}/${NAME} \
    store add file https://get.rke2.io --name install.sh

  for FILE in ${RKE2_FILES[@]}; do
  hauler --store ${STORE_DIR}/${NAME} \
    store add file ${RKE2_SOURCE}/${RKE2_VERSION_URL}/${FILE}
  done

  hauler --store ${STORE_DIR}/${NAME} \
    store save --filename ${OUTPUT_DIR}/${NAME}.tar.zst
}

load() {
  # Load RKE2 Archive
  hauler --store ${STORE_DIR}/rke2-${RKE2_VERSION} \
    store load --filename ${OUTPUT_DIR}/rke2-${RKE2_VERSION}.tar.zst

  # Load Chart archives
  for CHART in "${CHARTS[@]}"; do
    IFS=";" read -r CHART_NAME CHART_REPO CHART_VERSION CHART_LOCAL_REPO <<< "${CHART}"

    hauler --store ${STORE_DIR}/${CHART_NAME}-${CHART_VERSION} \
      store load --filename ${OUTPUT_DIR}/chart-${CHART_NAME}-${CHART_VERSION}.tar.zst

  done

  # Load Rancher archive
  hauler --store ${STORE_DIR}/rancher-${RANCHER_VERSION} \
    store load --filename ${OUTPUT_DIR}/rancher-${RANCHER_VERSION}.tar.zst

}

upload() {
  # Upload chart and their images
  for CHART in "${CHARTS[@]}"; do
    IFS=";" read -r CHART_NAME CHART_REPO CHART_VERSION CHART_LOCAL_REPO <<< "${CHART}"

    if [[ ! -z "${CHART_LOCAL_REPO}" ]]; then
      REGISTRY="registry://${LOCAL_REGISTRY}/${CHART_LOCAL_REPO}"
    else
      REGISTRY="registry://${LOCAL_REGISTRY}"
    fi

    hauler --store ${STORE_DIR}/${CHART_NAME}-${CHART_VERSION} \
      store copy ${REGISTRY}
  done

  # Upload Rancher artifacts
  if [[ ! -z "${LOCAL_REGISTRY_RANCHER_PROJECT}" ]]; then
    REGISTRY="registry://${LOCAL_REGISTRY}/${LOCAL_REGISTRY_RANCHER_PROJECT}"
  else
    REGISTRY="registry://${LOCAL_REGISTRY}"
  fi

  hauler --store ${STORE_DIR}/rancher-${RANCHER_VERSION} \
      store copy ${REGISTRY}

}

extract() {
  mkdir -p $EXTRACT_DIR

  hauler --store ${STORE_DIR}/rke2-${RKE2_VERSION} \
    store extract install.sh --output ${EXTRACT_DIR}

  for FILE in ${RKE2_FILES[@]}; do
  hauler --store ${STORE_DIR}/rke2-${RKE2_VERSION} \
    store extract ${FILE} --output ${EXTRACT_DIR}
  done

}

show_help() {
  echo "Rancher and RKE2 Download Script for Airgapped Enviroments"
  echo
  echo "Usage: artifacts.sh <command>"
  echo
  echo "Commands:"
  echo "  download Download all artifacts"
  echo "  load     Import artifacts archives into hauler"
  echo "  upload   Upload artifacts to registry"
  echo "  charts   Download charts artifacts"
  echo "  rancher  Download rancher artifacts"
  echo "  rke2     Download rke2 artifacts"
  echo "  extract  Extract rke2 artifacts"
}


case $1 in
  charts)
    get_charts
    ;;
  rancher)
    get_rancher_artifacts
    ;;
  rke2)
    get_rke2_artifacts
    ;;
  download)
    get_charts
    get_rancher_artifacts
    get_rke2_artifacts
    ;;
  upload)
    upload
    ;;
  load)
    load
    ;;
  extract)
    extract
    ;;
  *)
    show_help
    ;;
esac
