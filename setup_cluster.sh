#!/usr/bin/env bash

user_help() {
  echo "Setup Openshift Cluster"
  echo "options:"
  echo "-t,   --type                  cluster type (host or member)"
  echo "-mn,  --member-ns             namespace where member-operator is running"
  echo "-hn,  --host-ns               namespace where host-operator is running"
  echo "-d,   --dev-cluster-48-hrs    setting up toolchain 48 hrs temparory dev cluster"
  exit 0
}

if [[ $# -lt 1 ]]; then
  user_help
fi

while test $# -gt 0; do
  case "$1" in
  -h | --help)
    user_help
    ;;
  -t | --type)
    shift
    if [ "$1" != "host" ] && [ "$1" != "member" ]; then
      echo $1
      echo "Please provide supported values i.e. host or member"
      user_help
      exit 1
    fi
    CLUSTER_TYPE=$1
    shift
    ;;
  -mn|--member-ns)
    shift
    MEMBER_OPERATOR_NS=$1
    shift
    ;;
  -hn|--host-ns)
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

function validate_env() {
  if [[ -z ${PULL_SECRET} ]]; then
    echo "Environment variable 'PULL_SECRET' is not set. Please set it. You can download it from https://cloud.redhat.com/openshift/install/aws/installer-provisioned"
    exit 1
  fi
  if [[ -z ${SSH_PUBLIC_KEY} ]]; then
    echo "Environment variable 'SSH_PUBLIC_KEY' is not set. Please set it."
    exit 1
  fi
}

function assign_default_namespace_values {
  if [[ -z ${MEMBER_OPERATOR_NS} ]]; then
    export MEMBER_OPERATOR_NS=toolchain-member-operator
  fi
  if [[ -z ${HOST_OPERATOR_NS} ]]; then
    export HOST_OPERATOR_NS=toolchain-host-operator
  fi
}

function deploy_operators() {
  if [[ ${CLUSTER_TYPE} == "host" ]]; then
    oc new-project "$HOST_OPERATOR_NS"
    MAILGUN_DOMAIN=$MAILGUN_DOMAIN MAILGUN_API_KEY=$MAILGUN_API_KEY NAMESPACE=$HOST_OPERATOR_NS envsubst < ./config/host_operator_secret.yaml | oc apply -f -
    if [[ -z ${CONSOLE_NAMESPACE} ]]; then
      export $CONSOLE_NAMESPACE="openshift-console"
      echo "setting up default CONSOLE_NAMESPACE i.e. $CONSOLE_NAMESPACE "
    fi
    if [[ -z ${CONSOLE_ROUTE_NAME} ]]; then
      export $CONSOLE_ROUTE_NAME="console"
      echo "setting up default CONSOLE_ROUTE_NAME i.e. $CONSOLE_ROUTE_NAME "
    fi
    if [[ -z ${CHE_NAMESPACE} ]]; then
      export $CHE_NAMESPACE="toolchain-che"
      echo "setting up default CHE_NAMESPACE i.e. $CHE_NAMESPACE "
    fi
    if [[ -z ${CHE_ROUTE_NAME} ]]; then
      export $CHE_ROUTE_NAME="che"
      echo "setting up default CHE_ROUTE_NAME i.e. $CHE_ROUTE_NAME "
    fi
    REGISTRATION_SERVICE_URL=$REGISTRATION_SERVICE_URL CONSOLE_NAMESPACE=$CONSOLE_NAMESPACE CONSOLE_ROUTE_NAME=$CONSOLE_ROUTE_NAME CHE_NAMESPACE=$CHE_NAMESPACE CHE_ROUTE_NAME=$CHE_ROUTE_NAME NAMESPACE=$HOST_OPERATOR_NS envsubst < ./config/host_operator_config.yaml | oc apply -f -
    NAME=host-operator OPERATOR_NAME=toolchain-host-operator NAMESPACE=$HOST_OPERATOR_NS envsubst < ./config/operator_deploy.yaml | oc apply -f -
    oc apply -f ./config/reg_service_route.yaml
  else
    oc new-project "$MEMBER_OPERATOR_NS"
    if [[ -z ${IDENTITY_PROVIDER} ]]; then
      export IDENTITY_PROVIDER="rhd"
      echo "setting up default IDENTITY_PROVIDER i.e. $IDENTITY_PROVIDER for identity provider configuration"
    fi
    IDENTITY_PROVIDER=$IDENTITY_PROVIDER NAMESPACE=$MEMBER_OPERATOR_NS envsubst < ./config/member_operator_config.yaml | oc apply -f -
    NAME=member-operator OPERATOR_NAME=toolchain-member-operator NAMESPACE=$MEMBER_OPERATOR_NS envsubst < ./config/operator_deploy.yaml | oc apply -f -
  fi
}

function setup_autoscaler() {
  if [[ ${CLUSTER_TYPE} == "member" ]]; then
    oc apply -f ./config/autoscaler/autoscaler.yaml

    # worker-us-east-1a MachineAutoscaler 
    # MACHINE_SET_NAME=$(oc get machinesets -n openshift-machine-api -o jsonpath='{.items[0].metadata.name}')
    # MACHINE_SET=${MACHINE_SET_NAME} MACHINE_AUTOSCALER_NAME=worker-us-east-1a envsubst <./config/autoscaler/machine_autoscaler.yaml | oc apply -f -

    # worker-us-east-1b MachineAutoscaler 
    MACHINE_SET_NAME=$(oc get machinesets -n openshift-machine-api -o jsonpath='{.items[1].metadata.name}')
    MACHINE_SET=${MACHINE_SET_NAME} MACHINE_AUTOSCALER_NAME=worker-us-east-1b envsubst <./config/autoscaler/machine_autoscaler.yaml | oc apply -f -

    # worker-us-east-1c MachineAutoscaler 
    # MACHINE_SET_NAME=$(oc get machinesets -n openshift-machine-api -o jsonpath='{.items[2].metadata.name}')
    # MACHINE_SET=${MACHINE_SET_NAME} MACHINE_AUTOSCALER_NAME=worker-us-east-1c envsubst <./config/autoscaler/machine_autoscaler.yaml | oc apply -f -

    NAMESPACE=$MEMBER_OPERATOR_NS envsubst <./config/autoscaler/buffer.yaml | oc apply -f -
  fi
}

function setup_tools_operators() {
  if [[ ${CLUSTER_TYPE} == "member" ]]; then
    # Che
    # namespace, operator-group, subscription
    oc apply -f ./config/operators/che/subscription.yaml
    while [[ "checlusters.org.eclipse.che" != $(oc get crd checlusters.org.eclipse.che -o jsonpath='{.metadata.name}' 2>/dev/null) ]]; do
      echo "waiting for CheCluster CRD to be available..."
      sleep 1
    done
    # CheCluster
    oc apply -f ./config/operators/che/che_cluster.yaml
    echo "Che operator installed"

    # Pipelines
    # subscription
    oc apply -f ./config/operators/pipelines/subscription.yaml
    while [[ "config.operator.tekton.dev" != $(oc get crd config.operator.tekton.dev -o jsonpath='{.metadata.name}' 2>/dev/null) ]]; do
      echo "waiting for Pipleines Config CRD to be available..."
      sleep 1
    done
    echo "OpenShift Pipelines operator installed"

    # Serverless
    # Serving
    # namespace, subscription
    oc apply -f ./config/operators/serverless/serving_subscription.yaml
    while [[ "knativeservings.operator.knative.dev" != $(oc get crd knativeservings.operator.knative.dev -o jsonpath='{.metadata.name}' 2>/dev/null) ]]; do
      echo "waiting for KnativeServing CRD to be available..."
      sleep 1
    done
    # KnativeServing
    oc apply -f ./config/operators/serverless/knative_serving.yaml
    echo "OpenShift Serverless operator installed"

    # Swich to Manual
    oc patch subscription eclipse-che -n toolchain-che -p '{"spec":{"installPlanApproval":"Manual"}}' --type=merge
    oc patch subscription serverless-operator -n openshift-operators -p '{"spec":{"installPlanApproval":"Manual"}}' --type=merge
    oc patch subscription openshift-pipelines-operator -n openshift-operators -p '{"spec":{"installPlanApproval":"Manual"}}' --type=merge
  fi
}

function setup_cluster() {
  echo "cluster type:$CLUSTER_TYPE"
  CONFIG_MANIFESTS=${CLUSTER_TYPE}_$(date +"%Y_%m_%d-%H_%M_%S")
  mkdir $CONFIG_MANIFESTS

  if [[ ${DEV_CLUSTER} == "true" ]]; then
    export AWS_PROFILE=openshift-dev
    PULL_SECRET=$PULL_SECRET SSH_PUBLIC_KEY=$SSH_PUBLIC_KEY envsubst <./config/devcluster_config.yaml | cat > ${CONFIG_MANIFESTS}/install-config.yaml
    sed -i -e "s/replaceme/"${CLUSTER_TYPE}-$(date +"%s")"/g" ${CONFIG_MANIFESTS}/install-config.yaml
  else
    export AWS_PROFILE=crt-robot
    PULL_SECRET=$PULL_SECRET SSH_PUBLIC_KEY=$SSH_PUBLIC_KEY envsubst <./config/${CLUSTER_TYPE}_config.yaml | cat > ${CONFIG_MANIFESTS}/install-config.yaml
  fi
  echo "AWS_PROFILE: $AWS_PROFILE set"
  echo "copied install config in $CONFIG_MANIFESTS"

  echo "starting cluster installation"
  openshift-install create cluster --dir $CONFIG_MANIFESTS
  rm -rf ${CLUSTER_TYPE}-config
  cp $PWD/$CONFIG_MANIFESTS/auth/kubeconfig ${CLUSTER_TYPE}-config
}

function login_to_cluster() {
  export KUBECONFIG=$PWD/$CONFIG_MANIFESTS/auth/kubeconfig
}

function setup_idp() {
  . setup_idp.sh
}

function create_crt_admins() {
  echo "creating crt-admins groups and binding 'cluster-admin' clusterrole"
  oc adm groups new crt-admins
  oc adm policy add-cluster-role-to-group --rolebinding-name=crt-cluster-admins cluster-admin crt-admins

  . create_users.sh
}

function setup_logging() {
  . setup_logging.sh
}

# https://docs.openshift.com/container-platform/4.2/applications/projects/configuring-project-creation.html#disabling-project-self-provisioning_configuring-project-creation
function remove_self_provisioner_role() {
  oc patch clusterrolebinding.rbac self-provisioners -p '{"subjects": null, "metadata": {"annotations":{"rbac.authorization.kubernetes.io/autoupdate": "false"}}}'
  oc adm policy remove-cluster-role-from-group self-provisioner system:authenticated:oauth
}

# https://docs.openshift.com/container-platform/4.5/applications/pruning-objects.html
function enabe_imagepruner() {
  oc patch imagepruner cluster -p '{"spec":{"suspend":false, "schedule":"0 0 * * *"}}' --type=merge
}

validate_env
assign_default_namespace_values
setup_cluster
login_to_cluster
if [[ -z ${CLIENT_SECRET} ]]; then
    echo "skipping RHD identity provider setup as environment variable 'CLIENT_SECRET' is not set"
else
    setup_idp
fi
create_crt_admins
remove_self_provisioner_role
enabe_imagepruner
deploy_operators
setup_logging
setup_autoscaler
setup_tools_operators