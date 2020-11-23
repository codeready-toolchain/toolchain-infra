#!/bin/bash

######################################################################################
## Install Prometheus operator
######################################################################################
function install_prometheus_operator() {
  echo "📦 installing the Prometheus operator..."
  export KUBECONFIG=$KUBECONFIG_HOST

  oc process -f config/monitoring/prometheus.tmpl.yaml \
    -p NAMESPACE="$TOOLCHAIN_OPERATOR_NS_HOST" \
    -p SA_NAME=prometheus-k8s \
    | oc apply -f -
  
  # needed by the `kube-rbac-proxy` sidecar to create TokenReviews and SubjectAccessReviews
  oc adm policy add-cluster-role-to-user kube-rbac-proxy -z prometheus-k8s -n "$TOOLCHAIN_OPERATOR_NS_HOST"
  
  echo "✅ done installing Prometheus operator"
  echo ""
}

######################################################################################
## Deploying Grafana
######################################################################################
function deploy_grafana() {
  echo "📦 deploying Grafana..."
  # fetch the route to Thanos Querier on member cluster and 
  export KUBECONFIG=$KUBECONFIG_MEMBER
  THANOS_QUERIER_URL_MEMBER="https://$(oc get route/thanos-querier -n openshift-monitoring -o json | jq -r '.status.ingress[0].host')"
  export THANOS_QUERIER_URL_MEMBER
  echo "route to Thanos Querier on member cluster: $THANOS_QUERIER_URL_MEMBER"
  
  # create a `grafana` serviceaccount which is allowed to access Prometheus (via kube-rbac-proxy)
  oc process -f config/monitoring/grafana_serviceaccount.tmpl.yaml \
    -p NAMESPACE="$TOOLCHAIN_OPERATOR_NS_MEMBER" \
    -p NAME=grafana \
    | oc apply -f -
  # needed to connect to Thanos Querier
  oc adm policy add-cluster-role-to-user cluster-monitoring-view -z grafana -n "$TOOLCHAIN_OPERATOR_NS_MEMBER"
  BEARER_TOKEN_MEMBER="$(oc serviceaccounts get-token grafana -n $TOOLCHAIN_OPERATOR_NS_MEMBER)"
  export BEARER_TOKEN_MEMBER

  # fetch the "local" route to Grafana on host cluster and retrieve SA token to use to connect to it
  export KUBECONFIG=$KUBECONFIG_HOST
  THANOS_QUERIER_URL_HOST="https://thanos-querier.openshift-monitoring.svc:9091"
  export THANOS_QUERIER_URL_HOST
  echo "route to Thanos Querier on host cluster: $THANOS_QUERIER_URL_HOST"
  PROMETHEUS_OPERATED_URL_HOST="https://prometheus-operated-secured.$TOOLCHAIN_OPERATOR_NS_HOST.svc:8443"
  export PROMETHEUS_OPERATED_URL_HOST
  echo "route to Prometheus (operated) on host cluster: $PROMETHEUS_OPERATED_URL_HOST"
  
  # create a `grafana` serviceaccount which is allowed to access Thanos Querier and Prometheus operated (via kube-rbac-proxy)
  oc process -f config/monitoring/grafana_serviceaccount.tmpl.yaml \
    -p NAMESPACE="$TOOLCHAIN_OPERATOR_NS_HOST" \
    -p NAME=grafana \
    | oc apply -f -
  # needed to connect to Thanos Querier
  oc adm policy add-cluster-role-to-user cluster-monitoring-view -z grafana -n "$TOOLCHAIN_OPERATOR_NS_HOST"
  BEARER_TOKEN_HOST="$(oc serviceaccounts get-token grafana -n $TOOLCHAIN_OPERATOR_NS_HOST)"
  export BEARER_TOKEN_HOST

   # use the 'oc create' commands along with the 'oc apply' to make sure the resources can be created or updated when they already exist
  oc create configmap -n "$TOOLCHAIN_OPERATOR_NS_HOST" grafana-sandbox-dashboard \
    --from-file=sandbox.json=config/monitoring/sandbox-dashboard.json \
    -o yaml --dry-run=client | oc apply -f - 
  oc process -f config/monitoring/grafana_app.tmpl.yaml \
    -p NAMESPACE="$TOOLCHAIN_OPERATOR_NS_HOST" \
    -p SA_NAME=grafana \
    -p THANOS_QUERIER_URL_HOST="$THANOS_QUERIER_URL_HOST" \
    -p PROMETHEUS_OPERATED_URL_HOST="$PROMETHEUS_OPERATED_URL_HOST" \
    -p THANOS_QUERIER_URL_MEMBER="$THANOS_QUERIER_URL_MEMBER" \
    -p BEARER_TOKEN_HOST="$BEARER_TOKEN_HOST" \
    -p BEARER_TOKEN_MEMBER="$BEARER_TOKEN_MEMBER" \
    | oc apply -f -
  echo "✅ done with deploying Grafana on $SERVER"
  echo ""
  echo "🖥  https://$(oc get route/grafana -n $TOOLCHAIN_OPERATOR_NS_HOST -o json | jq -r '.status.ingress[0].host')"
}

######################################################################################
## Main
######################################################################################
if [[ -z ${KUBECONFIG_HOST} ]]; then
  echo "Missing 'KUBECONFIG_HOST' env var"
  exit 1
elif [[ -z ${KUBECONFIG_MEMBER} ]]; then
  echo "Missing 'KUBECONFIG_MEMBER' env var"
  exit 1
elif [[ -z ${TOOLCHAIN_OPERATOR_NS_HOST} ]]; then
  echo "Missing 'TOOLCHAIN_OPERATOR_NS_HOST' env var"
  exit 1
elif [[ -z ${TOOLCHAIN_OPERATOR_NS_MEMBER} ]]; then
  echo "Missing 'TOOLCHAIN_OPERATOR_NS_MEMBER' env var"
  exit 1
fi

export KUBECONFIG=$KUBECONFIG_HOST
  SERVER="$(oc whoami --show-server)"
  export SERVER
  read -p "ℹ️  Install Prometheus operator and Grafana on $SERVER in namespace '$TOOLCHAIN_OPERATOR_NS_HOST'? (y/n) " -r
  if [[ ! $REPLY =~ ^[Yy]$ ]]
  then
      exit 1
  fi

install_prometheus_operator
deploy_grafana
