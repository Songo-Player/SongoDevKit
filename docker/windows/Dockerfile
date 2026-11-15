# Everything Windows, on a Linux host:
#   - Songodot's Windows export template and editor, and SongoBGPlayer's
#     engine DLL with its mbedTLS and FFmpeg (MinGW-w64 GCC, posix threads,
#     since the engine uses std::thread; CROSS_PREFIX=x86_64-w64-mingw32-)
#   - the release packaging: ImageMagick for the icon, Wine to run rcedit on
#     the .exe, and NSIS for the installer
#
# Songodot and the engine DLL it loads share this one toolchain, so they agree
# on things like the monotonic clock behind std::chrono.

FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        gcc-mingw-w64-x86-64-posix \
        g++-mingw-w64-x86-64-posix \
        binutils-mingw-w64-x86-64 \
        gcc \
        libc6-dev \
        cmake \
        make \
        pkg-config \
        python3 \
        scons \
        rsync \
        ca-certificates \
        imagemagick \
        nsis \
        wine \
        wine64 \
    && rm -rf /var/lib/apt/lists/* \
    && update-alternatives --set x86_64-w64-mingw32-gcc /usr/bin/x86_64-w64-mingw32-gcc-posix \
    && update-alternatives --set x86_64-w64-mingw32-g++ /usr/bin/x86_64-w64-mingw32-g++-posix

ENV CROSS_PREFIX=x86_64-w64-mingw32-
ENV WINEDEBUG=-all
# No Mono/Gecko install prompts, rcedit needs neither
ENV WINEDLLOVERRIDES="mscoree,mshtml="
