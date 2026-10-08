FROM ghcr.io/cirruslabs/flutter:3.41.6

# Linux desktop toolchain + libs the app links against.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      clang cmake ninja-build pkg-config libgtk-3-dev libsecret-1-dev \
      libsqlite3-dev libglu1-mesa xvfb git curl ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# Docker CLI so the dev stack (docker/docker-compose.yml) can be started from inside the container.
COPY --from=docker:27-cli /usr/local/bin/docker /usr/local/bin/docker
COPY --from=docker:27-cli /usr/local/libexec/docker/cli-plugins/docker-compose /usr/local/libexec/docker/cli-plugins/docker-compose

ENV DISPLAY=:99
