#!/bin/sh

VERSION=v2.15.3

SRC_REGISTRY="registry.rancher.com"
DST_REGISTRY="registry.lab.suse"

IMAGE_TARS="$HOME/tmp/rancher/images"

curl -q -L https://prime.ribs.rancher.io/rancher/$VERSION/rancher-images.txt -o rancher-images-$VERSION.txt

# for IMAGE in `cat rancher-images-$VERSION.txt`; do
#     crane copy  $SRC_REGISTRY/$IMAGE $DST_REGISTRY/$IMAGE
# done

for IMAGE in `cat rancher-images-$VERSION.txt`; do

    TAR_PATH="$IMAGE_TARS/$VERSION/$IMAGE.tar"
    if [ ! -f "$TAR_PATH" ]; then
        echo "Download and save $VERSION/$IMAGE"
        mkdir -p "$(dirname "$TAR_PATH")"
        crane pull  $SRC_REGISTRY/$IMAGE "$TAR_PATH"
    else
        echo "Skip $VERSION/$IMAGE, file exists"
    fi
    echo "---------------------------------------------------------"
done

for IMAGE in `cat rancher-images-$VERSION.txt`; do
    echo "Upload $VERSION/$IMAGE"
    crane push  $IMAGE_TARS/$VERSION/$IMAGE.tar $DST_REGISTRY/$IMAGE
    echo "---------------------------------------------------------"
done
