#!/bin/sh

NAMESPACE=${1-default}
kubectl \
    --namespace=$NAMESPACE \
    create secret \
    docker-registry application-collection \
    --docker-server=dp.apps.rancher.io \
    --docker-username=$APPCO_USERNAME \
    --docker-password=$APPCO_PASSWORD