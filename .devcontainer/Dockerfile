# Querya Desktop dev container: Flutter (pinned to the CI version) + the Linux
# desktop toolchain + the Docker CLI for the database stack.
FROM ubuntu:24.04

# Keep in step with `flutter-version` in .github/workflows/ci.yml
# (test/guards/devcontainer_flutter_version_test.dart fails when they differ).
ARG FLUTTER_VERSION=3.47.1

ENV DEBIAN_FRONTEND=noninteractive \
    FLUTTER_HOME=/opt/flutter \
    PUB_CACHE=/root/.pub-cache
ENV PATH=/opt/flutter/bin:/opt/flutter/bin/cache/dart-sdk/bin:/root/.pub-cache/bin:$PATH

# Linux desktop toolchain + libs the app links against; bubblewrap for the
# extension sandbox tests; socat to forward localhost ports to the databases.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      build-essential clang cmake ninja-build pkg-config libgtk-3-dev \
      libsecret-1-dev libsqlite3-dev liblzma-dev libglu1-mesa xvfb \
      git curl unzip xz-utils zip ca-certificates bubblewrap socat \
 && rm -rf /var/lib/apt/lists/*

# Flutter at the pinned tag (the cirruslabs image registry has no 3.47.x tag).
RUN git config --system --add safe.directory /opt/flutter \
 && git clone --depth 1 --branch "${FLUTTER_VERSION}" \
      https://github.com/flutter/flutter.git /opt/flutter \
 && flutter config --no-analytics --enable-linux-desktop \
 && flutter precache --linux

# Docker CLI so the dev stack (docker/docker-compose.yml) can be started from inside the container.
COPY --from=docker:27-cli /usr/local/bin/docker /usr/local/bin/docker
COPY --from=docker:27-cli /usr/local/libexec/docker/cli-plugins/docker-compose /usr/local/libexec/docker/cli-plugins/docker-compose

ENV DISPLAY=:99
