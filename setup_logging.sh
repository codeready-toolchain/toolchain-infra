#!/usr/bin/env bash

function setup_logging() {
    echo "installing Cluster Logging and EFK operators..."
    oc create -f cluster-logging/eo-namespace.yaml
    oc create -f cluster-logging/clo-namespace.yaml
    oc create -f cluster-logging/eo-og.yaml
    oc create -f cluster-logging/eo-sub.yaml
    oc create -f cluster-logging/eo-rbac.yaml
    oc create -f cluster-logging/clo-og.yaml
    oc create -f cluster-logging/clo-sub.yaml
    oc create -f cluster-logging/instance.yaml

}

setup_logging
