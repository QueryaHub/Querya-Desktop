# querya-headless: the extension tester of a Querya Desktop release in a pinned,
# reproducible environment, to run in CI or locally without a display, Flutter
# or the Querya source tree.
#
#   docker build -f docker/headless/Dockerfile \
#     --build-arg QUERYA_VERSION=0.4.19 -t querya-headless:0.4.19 docker/headless
#
#   docker run --rm -v "$PWD/dist:/ext:ro" querya-headless:0.4.19 /ext \
#     --connect '{"host":"db","port":5432}' --trace /out/trace.json
#
# The tester is downloaded from the GitHub Release and checked against its
# SHA256SUMS.txt; the build fails when the checksum does not match.
#
# glibc (Debian) on purpose: extension entry points are native executables, and
# most of them are not linked against musl.
FROM debian:bookworm-slim

ARG QUERYA_VERSION
ARG TARGET=linux-x64

RUN test -n "${QUERYA_VERSION}" || (echo "set --build-arg QUERYA_VERSION=x.y.z" >&2; exit 1)

# bubblewrap is the OS sandbox of `--sandbox`; curl and tar fetch the tester.
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl tar bubblewrap \
 && rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    base="https://github.com/QueryaHub/Querya-Desktop/releases/download/${QUERYA_VERSION}"; \
    asset="querya-ext-tester-v${QUERYA_VERSION}-${TARGET}.tar.gz"; \
    cd /tmp; \
    curl -fsSLO "${base}/${asset}"; \
    curl -fsSLO "${base}/SHA256SUMS.txt"; \
    grep " ${asset}\$" SHA256SUMS.txt | sha256sum -c -; \
    tar -xzf "${asset}" -C /usr/local/bin querya-ext-tester; \
    rm -f "${asset}" SHA256SUMS.txt; \
    querya-ext-tester --help > /dev/null

LABEL org.opencontainers.image.title="querya-headless" \
      org.opencontainers.image.description="Querya Desktop extension tester (headless)" \
      org.opencontainers.image.source="https://github.com/QueryaHub/Querya-Desktop" \
      org.opencontainers.image.version="${QUERYA_VERSION}"

RUN useradd --create-home --uid 1000 querya
USER querya
WORKDIR /ext

ENTRYPOINT ["querya-ext-tester"]
CMD ["--help"]
