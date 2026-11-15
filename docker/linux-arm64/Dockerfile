# Cross compiles for arm64 Linux handhelds on an x86_64 host:
#   - Songodot's SBC export template (clang/lld 10, the arm64 libraries below
#     as its sysroot, SYSROOT_PATH=/)
#   - SongoBGPlayer's engine and daemon, with its mbedTLS and FFmpeg
#     (aarch64-linux-gnu GCC 9.4, CROSS_PREFIX=aarch64-linux-gnu-)
#
# Ubuntu 20.04 on purpose: its glibc (2.31) is what the earlier chroot builds
# used, so the binaries need glibc 2.29 and run on the same CFWs. Don't move
# to a newer release without checking the oldest CFW you support.
#
# The arm64 libraries are multiarch packages, so "/" doubles as the sysroot:
# libc and crt files in /usr/lib/aarch64-linux-gnu, GCC 10's runtime in
# /usr/lib/gcc/aarch64-linux-gnu/10, where clang looks for them.

FROM ubuntu:20.04

ENV DEBIAN_FRONTEND=noninteractive

# arm64 packages come from ports.ubuntu.com, so the main archive is limited
# to amd64. The native gcc is for the host tools FFmpeg's build runs.
RUN dpkg --add-architecture arm64 \
    && sed -i 's/^deb /deb [arch=amd64] /' /etc/apt/sources.list \
    && printf '%s\n' \
        "deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports focal main universe" \
        "deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports focal-updates main universe" \
        "deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports focal-security main universe" \
        > /etc/apt/sources.list.d/arm64-ports.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        clang-10 \
        lld-10 \
        llvm-10 \
        binutils-aarch64-linux-gnu \
        gcc-aarch64-linux-gnu \
        g++-aarch64-linux-gnu \
        gcc \
        libc6-dev \
        cmake \
        make \
        pkg-config \
        python3 \
        python3-pip \
        rsync \
        ca-certificates \
        libc6-dev:arm64 \
        libgcc-10-dev:arm64 \
        libstdc++-10-dev:arm64 \
        zlib1g-dev:arm64 \
        libsdl2-dev:arm64 \
        libasound2-dev:arm64 \
    && rm -rf /var/lib/apt/lists/*

# SCons 4, newer than focal's
RUN python3 -m pip install --no-cache-dir scons==4.7.0

# platform/sbc/detect.py calls plain clang/clang++, and looks for llvm-ar,
# llvm-ranlib and ld.lld on PATH
RUN cd /usr/local/bin \
    && ln -s /usr/bin/clang-10 clang \
    && ln -s /usr/bin/clang++-10 clang++ \
    && ln -s /usr/bin/ld.lld-10 ld.lld \
    && ln -s /usr/bin/llvm-ar-10 llvm-ar \
    && ln -s /usr/bin/llvm-ranlib-10 llvm-ranlib

# pkg-config sees the arm64 .pc files (SDL2 for Songodot), not the host's.
# A wrapper rather than an ENV, since SCons' ParseConfig doesn't pass
# PKG_CONFIG_* through. It keeps a PKG_CONFIG_LIBDIR that's already set, which
# SongoBGPlayer's FFmpeg build uses to only show it its own mbedTLS.
RUN printf '%s\n' \
        '#!/bin/sh' \
        'export PKG_CONFIG_LIBDIR="${PKG_CONFIG_LIBDIR:-/usr/lib/aarch64-linux-gnu/pkgconfig:/usr/share/pkgconfig}"' \
        'exec /usr/bin/pkg-config "$@"' \
        > /usr/local/bin/pkg-config \
    && chmod +x /usr/local/bin/pkg-config

ENV SYSROOT_PATH=/
