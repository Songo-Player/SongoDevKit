# Android builds and exports, with the SDK, NDK and JDK inside:
#   - Songodot's Android templates and Gradle source template
#   - SongoBGPlayer's Android engine and plugin AAR
#   - the Android export, which runs Songodot's editor (from the
#     linux-x86_64 image, glibc 2.35) and Godot's Gradle build
#
# The SDK's license is accepted below, so this image is fine to build and use
# locally but shouldn't be pushed to a public registry.

FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        openjdk-17-jdk-headless \
        build-essential \
        pkg-config \
        python3 \
        python3-pip \
        cmake \
        make \
        rsync \
        git \
        unzip \
        curl \
        binutils \
        ca-certificates \
        libfontconfig1 \
    && rm -rf /var/lib/apt/lists/*

RUN python3 -m pip install --no-cache-dir scons==4.7.0

ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
ENV ANDROID_HOME=/opt/android-sdk
ENV ANDROID_NDK_ROOT=/opt/android-sdk/ndk/23.2.8568313

# The SDK command line tools (pinned), then what Songo builds with: Godot
# 4.3's SDK 34, build-tools 34.0.0 and NDK r23c
RUN mkdir -p "$ANDROID_HOME/cmdline-tools" \
    && curl -fsSL -o /tmp/cmdline-tools.zip https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip \
    && unzip -q /tmp/cmdline-tools.zip -d /tmp \
    && mv /tmp/cmdline-tools "$ANDROID_HOME/cmdline-tools/latest" \
    && rm /tmp/cmdline-tools.zip \
    && yes | "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" --licenses > /dev/null \
    && "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" --install \
        "platform-tools" \
        "platforms;android-34" \
        "build-tools;34.0.0" \
        "ndk;23.2.8568313" \
        > /dev/null \
    && chmod -R a+rX "$ANDROID_HOME"

ENV PATH="$JAVA_HOME/bin:$ANDROID_HOME/platform-tools:$PATH"
