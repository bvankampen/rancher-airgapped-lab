#!/bin/sh

echo -n $SUSE_REGISTRY_PASSWORD | helm registry login registry.suse.com -u $SUSE_REGISTRY_USERNAME --password-stdin