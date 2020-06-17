#!/usr/bin/env bash
set -o nounset
set -o pipefail
set -o errexit

DIR="$(dirname $0)"

if [[ -z $AZURE_STORAGE_ACCOUNT ]]; then echo "ERROR: Env variable AZURE_STORAGE_ACCOUNT is not set"; exit 1; fi
if [[ -z $AZURE_STORAGE_KEY ]]; then echo "ERROR: Env variable AZURE_STORAGE_KEY is not set"; exit 1; fi

# create build dir
mkdir -p $DIR/build

# clone kubernetes repository
rm -rf $DIR/build/kubernetes
git clone https://github.com/kubernetes/kubernetes $DIR/build/kubernetes
pushd $DIR/build/kubernetes

# build Linux binaries and Docker images
make quick-release

# build Windows binaries
./build/run.sh make cross KUBE_BUILD_PLATFORMS=windows/amd64

popd

CI_VERSION=`$DIR/build/kubernetes/_output/dockerized/bin/linux/amd64/kubeadm version -o=short`
ARTIFACTS_DIR="$DIR/build/artifacts"
mkdir -p $ARTIFACTS_DIR

# copy Linux binaries to artifacts
for i in linux/amd64/kubectl \
         linux/amd64/kubelet \
         linux/amd64/kubeadm \
         windows/amd64/kubectl.exe \
         windows/amd64/kubelet.exe \
         windows/amd64/kubeadm.exe \
         windows/amd64/kube-proxy.exe; do
    mkdir -p `dirname $ARTIFACTS_DIR/$CI_VERSION/bin/$i`
    cp $DIR/build/kubernetes/_output/dockerized/bin/$i $ARTIFACTS_DIR/$CI_VERSION/bin/$i
done

# copy Linux Docker images to artifacts
mkdir -p $ARTIFACTS_DIR/$CI_VERSION/images
for i in kube-apiserver.tar \
         kube-controller-manager.tar \
         kube-scheduler.tar \
         kube-proxy.tar; do
    cp $DIR/build/kubernetes/_output/release-images/amd64/$i $ARTIFACTS_DIR/$CI_VERSION/images
done
chmod 644 $ARTIFACTS_DIR/$CI_VERSION/images/*

# upload artifacts
pushd $ARTIFACTS_DIR
for FILE in `find $CI_VERSION -type f`; do
    echo "Uploading: $FILE"
    az storage blob upload -c builds -f $FILE -n $FILE -o table
done
popd

# cross-build kube-proxy Windows Docker image
# TODO: adjust to CI environment
DOCKER_CLI_EXPERIMENTAL=enabled docker buildx build -f $DIR/kube-proxy/ds-windows.Dockerfile \
                    -t docker.io/ionutbalutoiu/kube-proxy-windows \
                    --build-arg k8sVersion=${CI_VERSION} \
                    --platform=windows/amd64 \
                    --push \
                    $DIR/build/artifacts/$CI_VERSION/bin/windows/amd64

# create artifacts env file
cat << EOF > $ARTIFACTS_DIR/env.sh
export CI_VERSION="$CI_VERSION"
EOF

# cleanup
rm -rf $DIR/build/kubernetes
docker system prune --all --force --volumes
