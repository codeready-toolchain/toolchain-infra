#!/usr/bin/env bash

user_help() {
  echo "Fetches API Server Logs and saves them as files in $PWD/logs dir"
  echo "Usage:"
  echo "    $> export KUBECONFIG=<path_to_master_or_host_kubeconfig>"
  echo "    $> ./fetch_logs"
  exit 0
}

while test $# -gt 0; do
  case "$1" in
  -h | --help)
    user_help
    ;;
  esac
done

function fetch_logs() {
    export LOGDIR=$PWD/logs
    mkdir -p ${LOGDIR}

    while read i; do
        read -r -a a <<< "$i"
        export NODE=${a[0]}
        export FILE=${a[1]}
        echo "Fetching $FILE from $NODE..."
        oc adm node-logs $NODE $FILE --path=openshift-apiserver/$FILE &> ${LOGDIR}/$NODE-$FILE
    done < <(oc --insecure-skip-tls-verify adm node-logs --role=master --path=openshift-apiserver/)
}

fetch_logs