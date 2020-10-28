#!/usr/bin/env bash

####################################################
## Enabling user workload monitoring
####################################################
function enable_user_workload_monitoring() {
  echo "🔬  enabling User Workload Monitoring"
  # see https://docs.openshift.com/container-platform/4.6/monitoring/configuring-the-monitoring-stack.html#preparing-to-configure-the-monitoring-stack
  # however, we may want to improve the script a little more (ie, check if the CM exist before creating them)
  oc apply -f config/monitoring/cluster_monitoring_config.yaml
  oc apply -f config/monitoring/user_workload_monitoring_config.yaml

  # at this point, there should be some new pods in the `openshift-user-workload-monitoring` namespace
  oc wait --for condition=Ready pods -l app=prometheus -n openshift-user-workload-monitoring
  echo "✅  done with enabling User Workload Monitoring"
}

####################################################
## Deploying Grafana
####################################################
function deploy_grafana() {
  echo "🚛  deploying Grafana..."
  oc create namespace toolchain-grafana
  oc apply -f config/monitoring/grafana_serviceaccount.yaml
  oc adm policy add-cluster-role-to-user cluster-monitoring-view -z grafana -n toolchain-grafana
  oc process -f config/monitoring/grafana_app.tmpl.yaml -p BEARER_TOKEN="$(oc serviceaccounts get-token grafana -n toolchain-grafana)" | oc apply -f -
  echo "✅  done with deploying Grafana"
  echo "🖥  https://$(oc get route/grafana -n toolchain-grafana -o json | jq -r '.status.ingress[0].host')"
}

enable_user_workload_monitoring
deploy_grafana