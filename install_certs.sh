#!/usr/bin/env bash

user_help() {
  echo "Install or Renew Let's Ecrypt Certificates"
  echo "Make sure you have acme.sh installed and AWS access credentials are set before before running this script:"
  echo "(see https://blog.openshift.com/requesting-and-installing-lets-encrypt-certificates-for-openshift-4/ for details)"
  echo ""
  echo "  1. Clone the acme.sh GitHub repository:"
  echo "      cd $HOME"
  echo "      git clone https://github.com/neilpang/acme.sh"
  echo "      cd acme.sh"
  echo "  2. Update the file $HOME/acme.sh/dnsapi/dns_aws.sh with your AWS access credentials:"
  echo "      #!/usr/bin/env sh"
  echo "      #AWS_ACCESS_KEY_ID=\"YOUR ACCESS KEY\""
  echo "      #AWS_SECRET_ACCESS_KEY=\"YOUR SECRET ACCESS KEY\""
  echo "      #This is the Amazon Route53 api wrapper for acme.sh"
  echo "      [...]"
  echo ""
  echo "options:"
  echo "-r,  --renew             renew existing certificates instead of issues new ones"
  echo "-h,  --help              print this help message"
  exit 0
}

while test $# -gt 0; do
  case "$1" in
  -h | --help)
    user_help
    ;;
  -r | --renew)
    RENEW_CERTS=true
    shift
    ;;
  *)
    echo "$1 is not a recognized flag!"
    user_help
    exit 1
    ;;
  esac
done

function login_to_cluster() {
  if [[ ${CLUSTER} == "host" ]]; then
    export KUBECONFIG=$PWD/host-config
  else
    export KUBECONFIG=$PWD/member-config
  fi
}

function install_cert() {
  export LE_API=$(oc whoami --show-server | cut -f 2 -d ':' | cut -f 3 -d '/' | sed 's/-api././')
  export LE_WILDCARD=$(oc get ingresscontroller default -n openshift-ingress-operator -o jsonpath='{.status.domain}')

  if [[ ${RENEW_CERTS} == "true" ]]; then
    FLAG="--renew"
  else
    FLAG="--issue"
  fi
  ${HOME}/acme.sh/acme.sh ${FLAG} -d ${LE_API} -d *.${LE_WILDCARD} --dns dns_aws

  export CERTDIR=$PWD/tmp/certificates/${CLUSTER}
  rm -rf ${CERTDIR} 2> /dev/null
  mkdir -p ${CERTDIR}
  ${HOME}/acme.sh/acme.sh --install-cert -d ${LE_API} -d *.${LE_WILDCARD} --cert-file ${CERTDIR}/cert.pem --key-file ${CERTDIR}/key.pem --fullchain-file ${CERTDIR}/fullchain.pem --ca-file ${CERTDIR}/ca.cer

  if [[ ${RENEW_CERTS} == "true" ]]; then
    oc delete secret tls router-certs -n openshift-ingress
  fi
  oc create secret tls router-certs --cert=${CERTDIR}/fullchain.pem --key=${CERTDIR}/key.pem -n openshift-ingress
  oc patch ingresscontroller default -n openshift-ingress-operator --type=merge --patch='{"spec": { "defaultCertificate": { "name": "router-certs" }}}'
}

function install_cert_in_host() {
  CLUSTER="host"
  login_to_cluster
  install_cert
}

function install_cert_in_member() {
  CLUSTER="member"
  login_to_cluster
  install_cert
}

install_cert_in_host
install_cert_in_member