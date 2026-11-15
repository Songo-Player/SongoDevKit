# x86_64 Linux builds, and running Songodot's editor for exports:
#   - Songodot's Linux editor (clang)
#   - SongoBGPlayer's x86_64 engine and daemon, with its mbedTLS and FFmpeg
#   - the PortMaster export and packaging
#
# Ubuntu 22.04: binaries need glibc 2.35, so the editor built here also runs
# on the host (most current distros) and in the android and windows images,
# which run it to export.

FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Godot's documented Linux build dependencies, plus what SongoBGPlayer and
# the packaging scripts use
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        clang \
        lld \
        llvm \
        pkg-config \
        python3 \
        python3-pip \
        libx11-dev \
        libxcursor-dev \
        libxinerama-dev \
        libgl1-mesa-dev \
        libglu1-mesa-dev \
        libasound2-dev \
        libpulse-dev \
        libudev-dev \
        libxi-dev \
        libxrandr-dev \
        libwayland-dev \
        wayland-protocols \
        libwayland-bin \
        cmake \
        make \
        rsync \
        git \
        binutils \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# SCons 4, newer than jammy's
RUN python3 -m pip install --no-cache-dir scons==4.7.0
