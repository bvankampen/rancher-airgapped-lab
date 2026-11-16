#!/bin/sh

echo -n $APPCO_PASSWORD | helm registry login dp.apps.rancher.io -u $APPCO_USERNAME --password-stdin