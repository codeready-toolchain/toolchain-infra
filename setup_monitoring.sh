#!/usr/bin/env bash


function login_to_cluster() {
  if [[ -z ${KUBECONFIG_HOST} ]]; then
    echo "Missing 'KUBECONFIG_HOST' env var"
    exit 1
  elif [[ -z ${KUBECONFIG_MEMBER} ]]; then
    echo "Missing 'KUBECONFIG_MEMBER' env var"
    exit 1
  fi

  if [[ ${CLUSTER} == "host" ]]; then
    export KUBECONFIG=$KUBECONFIG_HOST
  else
    export KUBECONFIG=$KUBECONFIG_MEMBER
  fi
  # echo "KUBECONFIG=$KUBECONFIG"
}

##########################################################################
## Enabling user workload monitoring on the server defined in $KUBECONFIG
##########################################################################
function enable_user_workload_monitoring_on_host() {
  echo "ℹ️ enabling User Workload Monitoring on Host cluster..."
  CLUSTER="host"
  login_to_cluster
  enable_user_workload_monitoring
}

function enable_user_workload_monitoring_on_member() {
  echo "ℹ️ enabling User Workload Monitoring on Member cluster..."
  CLUSTER="member"
  login_to_cluster
  enable_user_workload_monitoring
}

function enable_user_workload_monitoring() {
  SERVER="$(oc whoami --show-server)"
  export SERVER
  read -p "connecting to $SERVER (Y/n)? " -r
  if [[ ! $REPLY =~ ^[Yy]$ ]]
  then
      exit 1
  fi

  # see https://docs.openshift.com/container-platform/4.6/monitoring/configuring-the-monitoring-stack.html#preparing-to-configure-the-monitoring-stack
  # however, we may want to improve the script a little more (ie, check if the CM exist before creating them)
  oc apply -f config/monitoring/cluster_monitoring_config.yaml
  oc apply -f config/monitoring/user_workload_monitoring_config.yaml

  # at this point, there should be some new pods in the `openshift-user-workload-monitoring` namespace
  oc wait --for condition=Ready pods -l app=prometheus -n openshift-user-workload-monitoring
  echo "✅ done with enabling User Workload Monitoring on on $SERVER"
  echo ""
}

##########################################################
## Deploying Grafana on the server defined in $KUBECONFIG
##########################################################

function deploy_grafana() {
  echo "🚛 deploying Grafana..."
  
  # fetch route to thanos on member cluster and retrieve SA token to use to connect to it
  CLUSTER="member"
  login_to_cluster
  THANOS_URL_MEMBER="https://$(oc get route/thanos-querier -n openshift-monitoring -o json | jq -r '.status.ingress[0].host')"
  export THANOS_URL_MEMBER
  oc process -f config/monitoring/grafana_namespace.tmpl.yaml \
    -p NAMESPACE=toolchain-member-monitoring \
    | oc apply -f -
  oc process -f config/monitoring/grafana_serviceaccount.tmpl.yaml \
    -p NAMESPACE=toolchain-member-monitoring \
    -p NAME=toolchain-member-monitoring \
    | oc apply -f -
  oc adm policy add-cluster-role-to-user cluster-monitoring-view -z toolchain-member-monitoring -n toolchain-member-monitoring
  BEARER_TOKEN_MEMBER="$(oc serviceaccounts get-token toolchain-member-monitoring -n toolchain-member-monitoring)"
  export BEARER_TOKEN_MEMBER

  # fetch "local" route to thanos on host cluster and retrieve SA token to use to connect to it
  CLUSTER="host"
  login_to_cluster
  THANOS_URL_HOST="https://thanos-querier.openshift-monitoring.svc:9091"
  export THANOS_URL_HOST
  oc process -f config/monitoring/grafana_namespace.tmpl.yaml \
    -p NAMESPACE=toolchain-host-monitoring \
    | oc apply -f -
  oc process -f config/monitoring/grafana_serviceaccount.tmpl.yaml \
    -p NAMESPACE=toolchain-host-monitoring \
    -p NAME=toolchain-host-monitoring \
    | oc apply -f -
  oc adm policy add-cluster-role-to-user cluster-monitoring-view -z toolchain-host-monitoring -n toolchain-host-monitoring
  BEARER_TOKEN_HOST="$(oc serviceaccounts get-token toolchain-host-monitoring -n toolchain-host-monitoring)"
  export BEARER_TOKEN_HOST
  
  # use the 'oc create' commands along with the 'oc apply' to make sure the resources can be created or updated when they already exist
  oc create configmap -n toolchain-host-monitoring grafana-sandbox-dashboard \
    --from-file=sandbox.json=config/monitoring/sandbox-dashboard.json \
    -o yaml --dry-run=client | oc apply -f - 
  oc process -f config/monitoring/grafana_app.tmpl.yaml \
    -p NAMESPACE="toolchain-host-monitoring" \
    -p SA_NAME="toolchain-host-monitoring" \
    -p BEARER_TOKEN_HOST="$BEARER_TOKEN_HOST" \
    -p THANOS_URL_HOST="$THANOS_URL_HOST" \
    -p BEARER_TOKEN_MEMBER="$BEARER_TOKEN_MEMBER" \
    -p THANOS_URL_MEMBER="$THANOS_URL_MEMBER" \
    | oc apply -f -
  echo "✅ done with deploying Grafana on $SERVER"
  echo ""
  echo "🖥 https://$(oc get route/grafana -n toolchain-host-monitoring -o json | jq -r '.status.ingress[0].host')"
}

# member cluster setup: enable User Workload Monitoring
enable_user_workload_monitoring_on_member

# host cluster setup: enable User Workload Monitoring and deploy Grafana
enable_user_workload_monitoring_on_host
deploy_grafana