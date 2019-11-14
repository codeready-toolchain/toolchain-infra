#!/usr/bin/env bash

user_help() {
  echo "Setup Toolchain"
  echo "options:"
  echo "-d,  --dev-cluster-48-hrs     setting up toolchain 48 hrs temparory dev cluster"
  exit 0
}

while test $# -gt 0; do
  case "$1" in
  -h | --help)
    user_help
    ;;
  -d | --dev-cluster-48-hrs)
    DEV_CLUSTER=true
    shift
    ;;
  *)
    echo "$1 is not a recognized flag!"
    user_help
    exit 1
    ;;
  esac
done

function setup_cluster() {
  echo "starting installtion of $1 cluster"
  exec ./setup_cluster.sh -t $1 $2
  echo "installation of $1 cluster is finished"
}

function setup_host_and_member_clusters() {
  echo "setting up host and member cluster"
  if [[ ${DEV_CLUSTER} == "true" ]]; then
    setup_cluster host -d &
    setup_cluster member -d &
  else
    setup_cluster host &
    setup_cluster member &
  fi
  wait
}

function setup_kubefed() {
  echo "setting up kubefed on host and member clusters"

  export KUBECONFIG=$PWD/host-config
  oc config rename-context admin host-admin
  sed -i -e "s/name: admin/name: host-admin/g; s/user: admin/user: host-admin/g" $PWD/host-config
  export KUBECONFIG=$PWD/member-config
  oc config rename-context admin member-admin
  sed -i -e "s/name: admin/name: member-admin/g; s/user: admin/user: member-admin/g" $PWD/member-config

  export KUBECONFIG=$PWD/host-config:$PWD/member-config
  MEMBER_NS=toolchain-member-operator
  HOST_NS=toolchain-host-operator
  curl -sSL https://raw.githubusercontent.com/dipak-pawar/toolchain-common/c81d071953d42558c2945e53b221678a2a5b3047/scripts/add-cluster.sh | bash -s -- -t member -mn ${MEMBER_NS} -hn ${HOST_NS} -kc ${KUBECONFIG}
  curl -sSL https://raw.githubusercontent.com/dipak-pawar/toolchain-common/c81d071953d42558c2945e53b221678a2a5b3047/scripts/add-cluster.sh | bash -s -- -t host -mn ${MEMBER_NS} -hn ${HOST_NS} -kc ${KUBECONFIG}
}

setup_host_and_member_clusters
setup_kubefed
