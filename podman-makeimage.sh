#!/bin/bash
set -xeo pipefail
cd "$(dirname "$0")"
source util/vars.sh

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


./podman-download.sh
./podman-generate.sh "$TARGET" "$VARIANT" "${ADDINS[@]}"


podman build --security-opt label=disable --tag "$IMAGE" .

podman container stop ffbuildreg
podman image rm -f ffbuilder
