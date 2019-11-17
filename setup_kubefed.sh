#!/usr/bin/env bash

function assign_default_namespace_values() {
  if [[ -z ${MEMBER_OPERATOR_NS} ]]; then
    export MEMBER_OPERATOR_NS=toolchain-member-operator
  fi
  if [[ -z ${HOST_OPERATOR_NS} ]]; then
    export HOST_OPERATOR_NS=toolchain-host-operator
  fi
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
  curl -sSL https://raw.githubusercontent.com/dipak-pawar/toolchain-common/c81d071953d42558c2945e53b221678a2a5b3047/scripts/add-cluster.sh | bash -s -- -t member -mn ${MEMBER_OPERATOR_NS} -hn ${HOST_OPERATOR_NS} -kc ${KUBECONFIG}
  curl -sSL https://raw.githubusercontent.com/dipak-pawar/toolchain-common/c81d071953d42558c2945e53b221678a2a5b3047/scripts/add-cluster.sh | bash -s -- -t host -mn ${MEMBER_OPERATOR_NS} -hn ${HOST_OPERATOR_NS} -kc ${KUBECONFIG}
}

assign_default_namespace_values
setup_kubefed
