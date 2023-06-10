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

./podman-generate.sh "$TARGET" "$VARIANT" "${ADDINS[@]}"

podman build --security-opt label=disable --tag "$IMAGE" .

podman image rm -f ffbuilder
