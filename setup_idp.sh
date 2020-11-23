#!/usr/bin/env bash

function setup_idp() {
  # setup RHD identity provider with required secret and oauth configuration
  echo "setting up RHD identity provider"
  if [[ -z ${ISSUER} ]]; then
    export ISSUER="https://sso.redhat.com/auth/realms/redhat-external"
    echo "setting up default ISSUER url i.e. $ISSUER for identity provider configuration"
  fi
  if [[ -z ${IDENTITY_PROVIDER} ]]; then
    export IDENTITY_PROVIDER="rhd"
    echo "setting up default IDENTITY_PROVIDER i.e. $IDENTITY_PROVIDER for identity provider configuration"
  fi
  if [[ -z ${MAPPING} ]]; then
    export MAPPING="lookup"
    echo "setting up default mapping method i.e. $MAPPING for identity provider configuration"
  fi
  CLIENT_SECRET=$CLIENT_SECRET envsubst <./config/oauth/rhd_idp_secret.yaml | oc apply -f -
  IDENTITY_PROVIDER=$IDENTITY_PROVIDER ISSUER=$ISSUER envsubst <./config/oauth/idp.yaml | oc apply -f -
}

if [[ -z ${CLIENT_SECRET} ]]; then
    echo "skipping RHD identity provider setup as environment variable 'CLIENT_SECRET' is not set"
else
    setup_idp
fi