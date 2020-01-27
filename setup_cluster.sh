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
    NAME=host-operator OPERATOR_NAME=toolchain-host-operator NAMESPACE=$HOST_OPERATOR_NS envsubst < ./config/operator_deploy.yaml | oc apply -f -
    oc apply -f ./config/reg_service_route.yaml
  else
    oc new-project "$MEMBER_OPERATOR_NS"
    NAME=member-operator OPERATOR_NAME=toolchain-member-operator NAMESPACE=$MEMBER_OPERATOR_NS envsubst < ./config/operator_deploy.yaml | oc apply -f -
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
  SERVER_URL=$(oc whoami --show-server)
}

function setup_idp() {
  # setup RHD identity provider with required secret and oauth configuration
  echo "setting up RHD identity provider"
  if [[ -z ${ISSUER} ]]; then
    export ISSUER="https://sso.redhat.com/auth/realms/redhat-external"
    echo "setting up default ISSUER url i.e. $ISSUER for identity provider configuration"
  fi
  CLIENT_SECRET=$CLIENT_SECRET envsubst <./config/oauth/rhd_idp_secret.yaml | oc apply -f -
  ISSUER=$ISSUER envsubst <./config/oauth/idp.yaml | oc apply -f -
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
 # oc annotate clusterrolebinding.rbac self-provisioners 'rbac.authorization.kubernetes.io/autoupdate=false'
  oc patch clusterrolebinding.rbac self-provisioners -p '{"subjects": null}'
  oc adm policy remove-cluster-role-from-group self-provisioner system:authenticated:oauth
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
deploy_operators
setup_logging