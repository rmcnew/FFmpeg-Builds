#!/bin/bash
mkdir -p builder_container
podman save --output ./builder_container/ffmpeg-linux64-nonfree-6.0_builder.tar ghcr.io/btbn/ffmpeg-builds/linux64-nonfree-6.0:latest
