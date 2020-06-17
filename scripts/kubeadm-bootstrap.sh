#!/usr/bin/env bash
set -o nounset
set -o pipefail
set -o errexit

if [[ $# -ne 1 ]]; then
    echo "USAGE: $0 <CI_VERSION>"
    exit 1
fi

CI_VERSION=$1
CI_PACKAGES_BASE_URL="https://capzwin.blob.core.windows.net/builds"
CI_PACKAGES=("kubectl" "kubelet" "kubeadm")
CI_IMAGES=("kube-apiserver" "kube-controller-manager" "kube-proxy" "kube-scheduler")

echo "* testing CI version $CI_VERSION"

systemctl stop kubelet

for CI_PACKAGE in "${CI_PACKAGES[@]}"; do
    PACKAGE_URL="$CI_PACKAGES_BASE_URL/$CI_VERSION/bin/linux/amd64/$CI_PACKAGE"
    echo "* downloading binary: $PACKAGE_URL"
    curl --fail -Lo /usr/bin/$CI_PACKAGE $PACKAGE_URL
    chmod +x /usr/bin/$CI_PACKAGE
done

systemctl start kubelet

CI_DIR="/tmp/k8s-ci"
mkdir -p $CI_DIR
for CI_IMAGE in "${CI_IMAGES[@]}"; do
    CI_IMAGE_URL="$CI_PACKAGES_BASE_URL/$CI_VERSION/images/$CI_IMAGE.tar"
    echo "* downloading package: $CI_IMAGE_URL"
    curl --fail -Lo "$CI_DIR/${CI_IMAGE}.tar" $CI_IMAGE_URL
    ctr -n k8s.io images import "$CI_DIR/$CI_IMAGE.tar"
    ctr -n k8s.io images tag "k8s.gcr.io/${CI_IMAGE}-amd64:${CI_VERSION//+/_}" "k8s.gcr.io/${CI_IMAGE}:${CI_VERSION//+/_}"
    # remove unused image tag
    ctr -n k8s.io image remove "k8s.gcr.io/${CI_IMAGE}-amd64:${CI_VERSION//+/_}"
    # cleanup cached node image
    crictl rmi "k8s.gcr.io/${CI_IMAGE}:v1.18.3"
done

echo "* checking binary versions"
echo "ctr version: $(ctr version)"
echo "kubeadm version: $(kubeadm version -o=short)"
echo "kubectl version: $(kubectl version --client=true --short=true)"
echo "kubelet version: $(kubelet --version)"
