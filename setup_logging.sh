#!/usr/bin/env bash

function setup_logging() {
    echo "installing Cluster Logging and EFK operators..."
    oc create -f cluster-logging/eo-namespace.yaml
    oc create -f cluster-logging/clo-namespace.yaml
    oc create -f cluster-logging/eo-og.yaml
    oc create -f cluster-logging/eo-sub.yaml
    oc create -f cluster-logging/clo-og.yaml
    oc create -f cluster-logging/clo-sub.yaml
    # wait until the CRD is available before creating the CR
    NEXT_WAIT_TIME=0
    while [[ -z `oc get crd clusterloggings.logging.openshift.io 2>/dev/null` ]]; do
		if [[ ${NEXT_WAIT_TIME} -eq 300 ]]; then \
		   OPERATOR_GROUP_NAME=`oc get operatorgroups --output=name -n openshift-logging | grep "openshift-logging-"`
		   SUBSCRIPTION_NAME=`oc get subscription --output=name -n openshift-logging | grep "cluster-logging"`
		   echo "reached timeout of waiting for CRD clusterloggings.logging.openshift.io to be available in the cluster - see following info for debugging:"
		   echo "================================ Subscription =================================="
		   oc get ${SUBSCRIPTION_NAME} -n openshift-logging -o yaml
		   exit 1
		fi
		echo "$(( NEXT_WAIT_TIME++ )). attempt of waiting for CRD clusterloggings.logging.openshift.io to be available in the cluster..."
		sleep 1
	done
    oc create -f cluster-logging/instance.yaml
    echo "you can run 'oc get routes --namespace=openshift-logging' to get the URL of the dashboard once the 'kibana' pods are available in this namespace"
}

setup_logging
