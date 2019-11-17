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

function wait_for_resources_to_exists() {
  REPO_NAME=$1
  NAMESPACE=$2
  SUBSCRIPTION_NAME=$REPO_NAME
  counter=1
  while [[ -z $(oc get sa ${REPO_NAME} -n ${NAMESPACE} 2>/dev/null) ]] || [[ -z $(oc get crd kubefedclusters.core.kubefed.io 2>/dev/null) ]]; do
    if [[ ${counter} -eq 180 ]]; then
      echo "reached timeout of waiting for ServiceAccount ${REPO_NAME} to be available in namespace ${NAMESPACE} and CRD kubefedclusters.core.kubefed.io to be available in the cluster - see following info for debugging:"
      echo "================================ CatalogSource =================================="
      oc get catalogsource codeready-toolchain-operators -n openshift-marketplace -o yaml
      echo "================================ CatalogSource Pod Logs =================================="
      oc logs $(oc get pods -l "marketplace.operatorSource=codeready-toolchain-operators" -n openshift-marketplace -o name) -n openshift-marketplace
      echo "================================ Subscription =================================="
      oc get subscription ${SUBSCRIPTION_NAME} -n ${NAMESPACE} -o yaml
      exit 1
    fi

    echo "$counter attempt of waiting for ServiceAccount ${REPO_NAME} in namespace ${NAMESPACE} and CRD kubefedclusters.core.kubefed.io to be available in the cluster"
    counter=$((counter + 1))
    sleep 1
  done
}

assign_default_namespace_values
wait_for_resources_to_exists host-operator $HOST_OPERATOR_NS
wait_for_resources_to_exists member-operator $MEMBER_OPERATOR_NS
setup_kubefed
