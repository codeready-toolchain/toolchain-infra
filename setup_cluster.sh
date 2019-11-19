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
    echo "Please set 'SSH_PUBLIC_KEY' environment variable."
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
    E2E_REPO_PATH=/tmp/codeready-toolchain/toolchain-e2e
    rm -rf ${E2E_REPO_PATH}
    git clone https://github.com/codeready-toolchain/toolchain-e2e.git ${E2E_REPO_PATH}
    PREVIOUS_DIR=$PWD
    cd $E2E_REPO_PATH
    oc new-project "$HOST_OPERATOR_NS"
    NAME=host-operator OPERATOR_NAME=toolchain-host-operator NAMESPACE=$HOST_OPERATOR_NS envsubst < $PREVIOUS_DIR/config/operator_deploy.yaml | oc apply -f -
    make get-registration-service-repo login-as-admin
    make deploy-registration HOST_NS=$HOST_OPERATOR_NS REG_IMAGE_NAME=quay.io/codeready-toolchain/registration-service:v0.1
    cd $PREVIOUS_DIR
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
    export ISSUER="https://developers.redhat.com/auth/realms/rhd"
    echo "setting up default ISSUER url i.e. $ISSUER for Identity provider configuration"
  fi
  CLIENT_SECRET=$CLIENT_SECRET envsubst <./config/oauth/rhd_idp_secret.yaml | oc apply -f -
  ISSUER=$ISSUER envsubst <./config/oauth/idp.yaml | oc apply -f -
}

function create_users() {
  echo "creating crt-admins groups and bind 'cluster-admin' clusterrole"
  oc adm groups new crt-admins
  oc adm policy add-cluster-role-to-group --rolebinding-name=crt-cluster-admins cluster-admin crt-admins

  declare -A users
  users=(
    [alkazako-crtadmin]=06abfd61-9cee-4705-b0cd-5423186e9153
    [dpawar-crtadmin]=18c2b531-50a0-4ce9-95bb-2090db5feca1
    [mjobanek-crtadmin]=18858c97-3bd4-43fe-9aa8-14ce22265119
    [nvirani-crtadmin]=2be89467-f2f1-4e14-b1ae-3bf84c8cef52
    [tkurian-crtadmin]=88b195e7-b064-41b7-8fb5-67d640c3703c
    [xcoulon-crtadmin]=b82cedcb-1600-4d0a-a49c-0e149e626733
  )
  USERS=""
  for i in "${!users[@]}"; do
    USER_NAME=$i
    USER_ID_FROM_SUB_CLAIM=${users[$i]}
    USER_NAME=$USER_NAME USER_ID_FROM_SUB_CLAIM=$USER_ID_FROM_SUB_CLAIM envsubst <./config/oauth/user.yaml | oc apply -f -
    USERS+="$USER_NAME "
  done
  USERS="${USERS%%*( )}"

  # Add this users under crt-admins groups
  oc adm groups add-users crt-admins $USERS
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
    echo "skippking RHD Identity Provider setup as environment variable 'CLIENT_SECRET' is not set"
else
    setup_idp
fi
create_users
remove_self_provisioner_role
deploy_operators
