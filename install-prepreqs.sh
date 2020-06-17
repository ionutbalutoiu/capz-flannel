#!/usr/bin/env bash
set -e
set -o pipefail

if [[ -z $KIND_VERSION ]]; then export KIND_VERSION="v0.8.1"; fi
if [[ -z $KUBECTL_VERSION ]]; then export KUBECTL_VERSION="v1.18.3"; fi
if [[ -z $CAPI_VERSION ]]; then export CAPI_VERSION="v0.3.6"; fi


# Install kind
echo "Installing kind ${KIND_VERSION}"
curl --fail -s -Lo /tmp/kind "https://github.com/kubernetes-sigs/kind/releases/download/${KIND_VERSION}/kind-linux-amd64"
chmod +x /tmp/kind
sudo mv /tmp/kind /usr/local/bin/kind

# Install kubectl
echo "Installing kubectl ${KUBECTL_VERSION}"
curl --fail -s -Lo /tmp/kubectl "https://storage.googleapis.com/kubernetes-release/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
chmod +x /tmp/kubectl
sudo mv /tmp/kubectl /usr/local/bin/kubectl

# Install clusterctl
echo "Installing clusterctl ${CAPI_VERSION}"
curl --fail -s -Lo /tmp/clusterctl "https://github.com/kubernetes-sigs/cluster-api/releases/download/${CAPI_VERSION}/clusterctl-linux-amd64"
chmod +x /tmp/clusterctl
sudo mv /tmp/clusterctl /usr/local/bin/clusterctl
