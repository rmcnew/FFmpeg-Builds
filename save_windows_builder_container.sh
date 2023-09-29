#!/bin/bash
mkdir -p builder_container
rm -f ./builder_container/ffmpeg-win64-nonfree-6.0_builder.tar
podman save --output ./builder_container/ffmpeg-win64-nonfree-6.0_builder.tar ghcr.io/btbn/ffmpeg-builds/win64-nonfree-6.0:latest
