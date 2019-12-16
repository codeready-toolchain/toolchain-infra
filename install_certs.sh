#!/usr/bin/env bash

## Make sure you have requested cert for the clusters domains before running this script:
## See https://blog.openshift.com/requesting-and-installing-lets-encrypt-certificates-for-openshift-4/ for details
#
# cd $HOME
# git clone https://github.com/neilpang/acme.sh
# cd acme.sh
# <Update the file $HOME/acme.sh/dnsapi/dns_aws.sh with your AWS access credentials...>
# 
## Then for each cluster:
# export LE_API=$(oc whoami --show-server | cut -f 2 -d ':' | cut -f 3 -d '/' | sed 's/-api././')
# export LE_WILDCARD=$(oc get ingresscontroller default -n openshift-ingress-operator -o jsonpath='{.status.domain}')
# ${HOME}/acme.sh/acme.sh --issue -d ${LE_API} -d *.${LE_WILDCARD} --dns dns_aws

function setup_kubeconfig() {
  echo "setting up kubeconfig files for both clusters host and member"
  export KUBECONFIG=$PWD/host-config
  oc config rename-context admin host-admin
  sed -i -e "s/name: admin/name: host-admin/g; s/user: admin/user: host-admin/g" $PWD/host-config
  export KUBECONFIG=$PWD/member-config
  oc config rename-context admin member-admin
  sed -i -e "s/name: admin/name: member-admin/g; s/user: admin/user: member-admin/g" $PWD/member-config

  export KUBECONFIG=$PWD/host-config:$PWD/member-config
}

function install_cert() {
  export LE_API=$(oc whoami --show-server | cut -f 2 -d ':' | cut -f 3 -d '/' | sed 's/-api././')
  export LE_WILDCARD=$(oc get ingresscontroller default -n openshift-ingress-operator -o jsonpath='{.status.domain}')

  rm -rf tmp
  mkdir tmp
  export CERTDIR=$PWD/tmp/certificates
  mkdir -p ${CERTDIR}
  ${HOME}/acme.sh/acme.sh --install-cert -d ${LE_API} -d *.${LE_WILDCARD} --cert-file ${CERTDIR}/cert.pem --key-file ${CERTDIR}/key.pem --fullchain-file ${CERTDIR}/fullchain.pem --ca-file ${CERTDIR}/ca.cer

  oc create secret tls router-certs --cert=${CERTDIR}/fullchain.pem --key=${CERTDIR}/key.pem -n openshift-ingress
  oc patch ingresscontroller default -n openshift-ingress-operator --type=merge --patch='{"spec": { "defaultCertificate": { "name": "router-certs" }}}'
}

setup_kubeconfig
oc config use-context host-admin
install_cert
oc config use-context member-admin
install_cert
