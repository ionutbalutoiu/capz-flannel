#!/usr/bin/env bash
set -o nounset
set -o pipefail
set -o errexit

# Check if the required environment variables are set
if [[ -z $CLUSTER_NAME ]]; then echo "ERROR: Env variable CLUSTER_NAME is not set"; exit 1; fi

if [[ -z $AZURE_SUBSCRIPTION_ID ]]; then echo "ERROR: Env variable AZURE_SUBSCRIPTION_ID is not set"; exit 1; fi
if [[ -z $AZURE_TENANT_ID ]]; then echo "ERROR: Env variable AZURE_TENANT_ID is not set"; exit 1; fi
if [[ -z $AZURE_CLIENT_ID ]]; then echo "ERROR: Env variable AZURE_CLIENT_ID is not set"; exit 1; fi
if [[ -z $AZURE_CLIENT_SECRET ]]; then echo "ERROR: Env variable AZURE_CLIENT_SECRET is not set"; exit 1; fi

if [[ -z $AZURE_LOCATION ]]; then echo "ERROR: Env variable AZURE_LOCATION is not set"; exit 1; fi
if [[ -z $AZURE_SSH_PUBLIC_KEY ]]; then echo "ERROR: Env variable AZURE_SSH_PUBLIC_KEY is not set"; exit 1; fi

if [[ -z $AZURE_CONTROL_PLANE_MACHINE_TYPE ]]; then echo "ERROR: Env variable AZURE_CONTROL_PLANE_MACHINE_TYPE is not set"; exit 1; fi
if [[ -z $AZURE_LINUX_NODE_MACHINE_TYPE ]]; then echo "ERROR: Env variable AZURE_LINUX_NODE_MACHINE_TYPE is not set"; exit 1; fi

if [[ -z $AZURE_WINDOWS_NODE_MACHINE_TYPE ]]; then echo "ERROR: Env variable AZURE_WINDOWS_NODE_MACHINE_TYPE is not set"; exit 1; fi
if [[ -z $AZURE_WINDOWS_NODE_IMAGE_RG ]]; then echo "ERROR: Env variable AZURE_WINDOWS_NODE_IMAGE_RG is not set"; exit 1; fi
if [[ -z $AZURE_WINDOWS_NODE_IMAGE_GALLERY ]]; then echo "ERROR: Env variable AZURE_WINDOWS_NODE_IMAGE_GALLERY is not set"; exit 1; fi
if [[ -z $AZURE_WINDOWS_NODE_IMAGE_DEFINITION ]]; then echo "ERROR: Env variable AZURE_WINDOWS_NODE_IMAGE_DEFINITION is not set"; exit 1; fi
if [[ -z $AZURE_WINDOWS_NODE_IMAGE_VERSION ]]; then echo "ERROR: Env variable AZURE_WINDOWS_NODE_IMAGE_VERSION is not set"; exit 1; fi

# Azure base64 variables
export AZURE_SUBSCRIPTION_ID_B64="$(echo -n "$AZURE_SUBSCRIPTION_ID" | base64 | tr -d '\n')"
export AZURE_TENANT_ID_B64="$(echo -n "$AZURE_TENANT_ID" | base64 | tr -d '\n')"
export AZURE_CLIENT_ID_B64="$(echo -n "$AZURE_CLIENT_ID" | base64 | tr -d '\n')"
export AZURE_CLIENT_SECRET_B64="$(echo -n "$AZURE_CLIENT_SECRET" | base64 | tr -d '\n')"
export AZURE_SSH_PUBLIC_KEY_B64=$(echo $AZURE_SSH_PUBLIC_KEY | base64 | tr -d '\n')

DIR="$(dirname $0)"

log() {
    echo "$(date '+%F %T') - $@"
}

# Start timer
SECONDS=0
START_SECONDS=$SECONDS

# build artifacts
log "Building artifacts"
$DIR/build-artifacts.sh

# source artifacts env
source $DIR/build/artifacts/env.sh
if [[ -z $CI_VERSION ]]; then echo "ERROR: Artifacts env variable CI_VERSION is not set"; exit 1; fi

# Print wait time & reset timer
WAIT_TIME="$(python3 -c "print('%f' % ((int($SECONDS) - int($START_SECONDS)) / 60.0))") minutes"
log "The artifacts build finished in $WAIT_TIME"
SECONDS=0
START_SECONDS=$SECONDS

# create the management cluster with kind
log "Creating kind management cluster"
kind create cluster --wait 5m

# add the cluster-api components to the management cluster
clusterctl init --infrastructure azure:v0.4.4 --config clusterctl-config.yaml

# wait for the patched deployments to be available
kubectl wait --for=condition=Available deployments --all --all-namespaces

# Print wait time & reset timer
WAIT_TIME="$(python3 -c "print('%f' % ((int($SECONDS) - int($START_SECONDS)) / 60.0))") minutes"
log "The kind management cluster provisioned in $WAIT_TIME"
SECONDS=0
START_SECONDS=$SECONDS

# deploy a new cluster
log "Deploying a new flannel-enabled cluster with: 1x control-plane, 1x Linux worker, 1x Windows worker"
cat $DIR/capi-cluster/control-plane.yaml | envsubst | kubectl apply -f -
cat $DIR/capi-cluster/md-linux.yaml | envsubst | kubectl apply -f -
cat $DIR/capi-cluster/md-windows.yaml | envsubst | kubectl apply -f -

# wait for the control-plane to be ready
while ! kubectl get machines 2>&1 | grep -q -o "${CLUSTER_NAME}-control-plane"; do
    log "Waiting for the control-plane machine(s)"; sleep 5; done
CONTROL_PLANE=$(kubectl get machines -o name | grep "${CLUSTER_NAME}-control-plane")
while [[ "$(kubectl get $CONTROL_PLANE -o json | jq -r '.status.phase')" != "Running" ]]; do
    log "Waiting for the control-plane to be running"; sleep 5; done

# fetch the kubeconfig for the new cluster
log "Fetching kubeconfig for the new cluster"
mkdir -p $DIR/build
kubectl get secret/${CLUSTER_NAME}-kubeconfig -o json | \
    jq -r .data.value | base64 --decode > $DIR/build/capi-cluster.kubeconfig

export KUBECONFIG=$DIR/build/capi-cluster.kubeconfig

# add the flannel CNI to the new cluster
log "Adding flannel CNI"
kubectl apply -f $DIR/kube-flannel/addons.yaml
kubectl apply -f $DIR/kube-flannel/ds-linux.yaml
kubectl apply -f $DIR/kube-flannel/ds-windows.yaml

# deploy kube-proxy on Windows
log "Adding kube-proxy daemonset on Windows"
cat $DIR/kube-proxy/ds-windows.yaml | kubectl apply -f -

unset KUBECONFIG

# wait for the Linux & Windows machines to be running
while ! kubectl get machines 2>&1 | grep -q -o "${CLUSTER_NAME}-linux"; do
    log "Waiting for the Linux agent machine(s)"; sleep 5; done
while ! kubectl get machines 2>&1 | grep -q -o "capi-win"; do
    log "Waiting for the Windows agent machine(s)"; sleep 5; done
while ! kubectl get machines -o json | $DIR/utils/check-machines-status.py; do
    sleep 5; done

export KUBECONFIG=$DIR/build/capi-cluster.kubeconfig

# wait for all the nodes in the new cluster to be ready
while ! kubectl get nodes 2>&1 | grep -q -o "${CLUSTER_NAME}-linux"; do
    log "Waiting for the Linux node(s)"; sleep 5; done
while ! kubectl get nodes 2>&1 | grep -q -o "capi-win"; do
    log "Waiting for the Windows node(s)"; sleep 5; done
while ! kubectl get nodes -o json | $DIR/utils/check-nodes-status.py; do
    sleep 5; done

# wait for all the pods to be ready
kubectl wait --for=condition=Ready --timeout 20m pods --all --all-namespaces

# Print wait time & reset timer
WAIT_TIME="$(python3 -c "print('%f' % ((int($SECONDS) - int($START_SECONDS)) / 60.0))") minutes"
log "The cluster provisioned in $WAIT_TIME"

# check if the CI version is properly setup
for NODE in $(kubectl get nodes -o name); do
    KUBELET_VERSION=$(kubectl get $NODE -o json | jq -r ".status.nodeInfo.kubeletVersion")
    if [[ "$KUBELET_VERSION" != "$CI_VERSION" ]]; then
        echo "ERROR: Node $NODE has kubelet version $KUBELET_VERSION. Expected: $CI_VERSION"
        exit 1
    fi
    KUBE_PROXY_VERSION=$(kubectl get $NODE -o json | jq -r ".status.nodeInfo.kubeProxyVersion")
    if [[ "$KUBE_PROXY_VERSION" != "$CI_VERSION" ]]; then
        echo "ERROR: Node $NODE has kubelet version $KUBELET_VERSION. Expected: $CI_VERSION"
        exit 1
    fi
done

# check if the Linux nodes have the proper images loaded
for NODE in $(kubectl get nodes -o name -l kubernetes.io/os=linux); do
    NON_CI_IMAGES=`kubectl get -o json $NODE | \
        jq -r '.status.images[] | select(.names[] | startswith("k8s.gcr.io/kube-")) | .names[]' \
        | sort | uniq | grep -v ${CI_VERSION//+/_}`
    if [[ "$NON_CI_IMAGES" != "" ]]; then
        echo "ERROR: Unexpected images found on node $NODE"
        echo $NON_CI_IMAGES
        exit 1
    fi
done

unset KUBECONFIG
