#!/bin/bash
set -xe
cd "$(dirname "$0")"
source util/podman-vars.sh

podman inspect ffbuilder &>/dev/null || podman create \
    --name=ffbuilder \
    --network=host \
    --env=BUILDKIT_STEP_LOG_MAX_SIZE=-1 \
    --env=BUILDKIT_STEP_LOG_MAX_SPEED=-1 \
    "$TARGET_IMAGE"


podman container inspect ffbuildreg &>/dev/null || \
    podman run --rm -d -p 127.0.0.1:64647:5000 --name ffbuildreg registry:2
LOCAL_REG_PORT="$(podman container inspect --format='{{range $p, $conf := .NetworkSettings.Ports}}{{(index $conf 0).HostPort}}{{end}}' ffbuildreg)"
LOCAL_ROOT="127.0.0.1:${LOCAL_REG_PORT}/local"

export REGISTRY_OVERRIDE_DL="127.0.0.1:${LOCAL_REG_PORT}" GITHUB_REPOSITORY_DL="local"


echo "Calling podman-generate.sh 1"
./podman-generate.sh "$TARGET" "$VARIANT" "${ADDINS[@]}"
DL_CACHE_TAG="$(./util/get_dl_cache_tag.sh)"
DL_IMAGE="${DL_IMAGE_RAW}:${DL_CACHE_TAG}"

if podman pull "${DL_IMAGE}"; then
    export REGISTRY_OVERRIDE_DL="$REGISTRY" GITHUB_REPOSITORY_DL="$REPO"
    echo "Calling podman-generate.sh 2"
    ./podman-generate.sh "$TARGET" "$VARIANT" "${ADDINS[@]}"
else
    DL_IMAGE="${LOCAL_ROOT}/dl_cache:${DL_CACHE_TAG}"
    podman manifest inspect --insecure "${DL_IMAGE}" >/dev/null ||
        podman build --security-opt label=disable -f Dockerfile.dl --tag "${DL_IMAGE}" .
fi

podman build --security-opt label=disable --tag "$IMAGE" .

podman container stop ffbuildreg
podman image rm -f ffbuilder
