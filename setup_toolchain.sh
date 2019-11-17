#!/usr/bin/env bash

user_help() {
  echo "Setup Toolchain"
  echo "options:"
  echo "-d,  --dev-cluster-48-hrs     setting up toolchain 48 hrs temparory dev cluster"
  echo "-mn,  --member-ns             namespace where member-operator is running"
  echo "-hn,  --host-ns               namespace where host-operator is running"
  exit 0
}

while test $# -gt 0; do
  case "$1" in
  -h | --help)
    user_help
    ;;
  -mn | --member-ns)
    shift
    MEMBER_OPERATOR_NS=$1
    shift
    ;;
  -hn | --host-ns)
    shift
    HOST_OPERATOR_NS=$1
    shift
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

function assign_default_namespace_values {
  if [[ -z ${MEMBER_OPERATOR_NS} ]]; then
    export MEMBER_OPERATOR_NS=toolchain-member-operator
  fi
  if [[ -z ${HOST_OPERATOR_NS} ]]; then
    export HOST_OPERATOR_NS=toolchain-host-operator
  fi
}

function setup_cluster() {
  echo "starting installtion of $1 cluster"
  exec ./setup_cluster.sh -t $1 -hn $2 -mn $3 $4
  echo "installation of $1 cluster is finished"
}

function setup_host_and_member_clusters() {
  echo "setting up host and member cluster"
  if [[ ${DEV_CLUSTER} == "true" ]]; then
    setup_cluster host $HOST_OPERATOR_NS $MEMBER_OPERATOR_NS -d &
    setup_cluster member $HOST_OPERATOR_NS $MEMBER_OPERATOR_NS -d &
  else
    setup_cluster host $HOST_OPERATOR_NS $MEMBER_OPERATOR_NS &
    setup_cluster member $HOST_OPERATOR_NS $MEMBER_OPERATOR_NS &
  fi
  wait
}

function setup_kubefed() {
    MEMBER_OPERATOR_NS=$MEMBER_OPERATOR_NS HOST_OPERATOR_NS=$HOST_OPERATOR_NS exec ./setup_kubefed.sh
}

assign_default_namespace_values
setup_host_and_member_clusters
setup_kubefed
