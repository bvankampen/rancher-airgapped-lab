#!/bin/sh
kubectl \
    --namespace=private-registry \
    create secret \
    docker-registry suse-registry \
    --docker-server=registry.suse.com \
    --docker-username=$SUSE_REGISTRY_USERNAME \
    --docker-password=$SUSE_REGISTRY_PASSWORD