#!/bin/sh

VERSION=1.21.3
CHART_NAME="cert-manager"
CHART_FILE=${CHART_NAME}-${VERSION}.tgz

DST_REGISTRY="registry.lab.suse/rancher/containers"
IMAGE_TARS="$HOME/tmp/cert-manager/images"

helm fetch oci://dp.apps.rancher.io/charts/cert-manager --version ${VERSION}

IMAGES=$(helm template ${CHART_FILE} | grep image: | awk -F "image:" '{ print $2 }' | tr -d ' "')

for FULL_IMAGE in $IMAGES; do
  IMAGE="${FULL_IMAGE##*/}"
  TAR_PATH="$IMAGE_TARS/$VERSION/$IMAGE.tar"

  if [ ! -f "$TAR_PATH" ]; then
      echo "Download and save $VERSION/$IMAGE"
      mkdir -p "$(dirname "$TAR_PATH")"
      crane pull  $FULL_IMAGE "$TAR_PATH"
  else
      echo "Skip $VERSION/$IMAGE, file exists"
  fi
  echo "---------------------------------------------------------"
done

for FULL_IMAGE in $IMAGES; do
  IMAGE="${FULL_IMAGE##*/}"
  TAR_PATH="$IMAGE_TARS/$VERSION/$IMAGE.tar"

  echo "Upload $VERSION/$IMAGE"
  crane push  "$TAR_PATH" $DST_REGISTRY/$IMAGE
  echo "---------------------------------------------------------"
done

rm ${CHART_FILE}
