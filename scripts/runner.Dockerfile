# Copyright (c) 2026- Tight Line LLC
# SPDX-License-Identifier: MIT

# The machine `make demo` runs the pipeline on: a Linux self-hosted runner
# with the Docker CLI, act and the tools the jobs use. The demo runs inside it
# so that it behaves the same on Linux and macOS.
FROM docker:27-cli
ARG ACT_VERSION=0.2.97
ARG TARGETARCH
RUN apk add --no-cache bash coreutils curl git nodejs openssl sed \
    && case "$TARGETARCH" in amd64) arch=x86_64 ;; arm64) arch=arm64 ;; *) echo "unsupported: $TARGETARCH" >&2; exit 1 ;; esac \
    && base="https://github.com/nektos/act/releases/download/v${ACT_VERSION}" \
    && file="act_Linux_${arch}.tar.gz" \
    && cd /tmp && curl -fsSLO "$base/$file" && curl -fsSLO "$base/checksums.txt" \
    && grep " ${file}\$" checksums.txt | sha256sum -c - \
    && tar xzf "$file" act && install act /usr/local/bin/ && rm -f act "$file" checksums.txt \
    && git config --system safe.directory '*'
