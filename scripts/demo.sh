#!/usr/bin/env bash
# Copyright (c) 2026- Tight Line LLC
# SPDX-License-Identifier: MIT

# Run the whole pipeline on this machine, as its runners would: the
# workflows in .github/workflows, exactly as `datadouble ci init` wrote them,
# run with act on the machine itself (a self-hosted runner, marked inside the
# production boundary for build and promote), against a throwaway source.
#
# It builds the Datadouble image from a checkout of datadouble/datadouble
# (DATADOUBLE_CHECKOUT, or a clone of DATADOUBLE_REF) and tags it as the
# release the workflows pin, and points their action at the same checkout.
# Needs Docker and git. It runs itself inside a Linux container that plays the
# self-hosted runner (scripts/runner.Dockerfile, which has act), so it behaves
# the same on Linux and macOS. Everything it makes is under
# /var/tmp/example-pipeline, on the Docker host, and removed at the end.
set -euo pipefail
cd "$(dirname "$0")/.."

# The runner container sees the repository, the Docker socket and /var/tmp at
# the same paths as the Docker host, because the jobs start containers that
# mount those paths. On macOS the Docker host is Docker's Linux VM.
if [ -z "${DEMO_RUNNER:-}" ]; then
    docker build --quiet --tag example-pipeline-runner --file scripts/runner.Dockerfile scripts > /dev/null
    mounts=(--volume "$PWD:$PWD")
    if [ -n "${DATADOUBLE_CHECKOUT:-}" ]; then
        DATADOUBLE_CHECKOUT=$(cd "$DATADOUBLE_CHECKOUT" && pwd)
        mounts+=(--volume "$DATADOUBLE_CHECKOUT:$DATADOUBLE_CHECKOUT")
    fi
    exec docker run --rm --volume /var/run/docker.sock:/var/run/docker.sock \
        --volume /var/tmp:/var/tmp "${mounts[@]}" --workdir "$PWD" \
        --env DEMO_RUNNER=1 --env DATADOUBLE_CHECKOUT --env DATADOUBLE_REF \
        example-pipeline-runner bash scripts/demo.sh
fi

base=/var/tmp/example-pipeline
network=example-pipeline
ref=${DATADOUBLE_REF:-main}
version=$(sed -n 's/.*uses: datadouble\/datadouble\/ci\/github-actions@\(v[^ ]*\).*/\1/p' \
    .github/workflows/datadouble-shop-build.yml)
image=ghcr.io/datadouble/datadouble:$version
work=$(mktemp -d /var/tmp/example-pipeline-demo.XXXXXX)

as_root() { docker run --rm --volume /var/tmp:/var/tmp --user 0:0 --entrypoint sh "$image" -c "$1"; }

cleanup() {
    docker rm --force --volumes example-pipeline-source > /dev/null 2>&1 || true
    docker network rm "$network" > /dev/null 2>&1 || true
    as_root "rm -rf $base $work" 2> /dev/null || rm -rf "$work"
}
trap cleanup EXIT

step() { printf '\n== %s\n' "$*"; }

checkout=${DATADOUBLE_CHECKOUT:-}
step "Datadouble $version, built from ${checkout:-datadouble/datadouble $ref}"
if [ -z "$checkout" ]; then
    checkout=$work/datadouble
    git clone --quiet --depth 1 --branch "$ref" https://github.com/datadouble/datadouble "$checkout"
fi
docker build --quiet --target runtime --tag "$image" "$checkout" > /dev/null

step "A throwaway source and the spec's directories"
password=$(openssl rand -hex 16)
docker network create --subnet 172.30.1.0/24 "$network" > /dev/null
POSTGRES_PASSWORD=$password docker run --detach --name example-pipeline-source \
    --network "$network" --ip 172.30.1.10 --env POSTGRES_PASSWORD pgvector/pgvector:0.8.7-pg18-trixie > /dev/null
docker exec example-pipeline-source timeout 60 sh -c \
    'until pg_isready --quiet --host 127.0.0.1 --username postgres; do sleep 1; done'
docker exec --interactive example-pipeline-source \
    psql --username postgres --quiet --set ON_ERROR_STOP=1 < source/shop.sql
as_root "install -d -o 999 -g 999 $base $base/store $base/export $base/work $base/staging $base/copies && install -d -m 0777 $base/keys"

step "A signing key pair"
cosign_password=$(openssl rand -hex 16)
docker run --rm --volume "$base/keys:$base/keys" --workdir "$base/keys" --user "$(id -u):$(id -g)" \
    --env COSIGN_PASSWORD="$cosign_password" --entrypoint cosign "$image" generate-key-pair > /dev/null

secrets=$work/secrets
{
    printf 'SHOP_SOURCE_DSN=postgresql://postgres:%s@172.30.1.10:5432/postgres\n' "$password"
    printf 'COSIGN_PASSWORD=%s\n' "$cosign_password"
    printf 'SHOP_COSIGN_KEY="%s"\n' "$(sed ':a;N;$!ba;s/\n/\\n/g' "$base/keys/cosign.key")"
    printf 'SHOP_COSIGN_PUB="%s"\n' "$(sed ':a;N;$!ba;s/\n/\\n/g' "$base/keys/cosign.pub")"
} > "$secrets"
# The pull request comes from this repository itself (its origin, which a
# fork's clone names too): the jobs never run one from somewhere else.
repository=$(git remote get-url origin 2> /dev/null | sed -E 's#.*github\.com[:/]##; s#\.git$##')
repository=${repository:-datadouble/example-pipeline}
printf '{"repository": {"full_name": "%s"}}\n' "$repository" > "$work/manual.json"
for action in opened closed; do
    printf '{"action": "%s", "number": 1, "repository": {"full_name": "%s"}, "pull_request": {"number": 1, "head": {"repo": {"full_name": "%s"}}}}\n' \
        "$action" "$repository" "$repository" > "$work/$action.json"
done

# act gets a clean environment: only what a self-hosted runner's machine has.
run() {
    local event=$1 workflow=$2 payload=$3
    step "$workflow ($event)"
    env -i "PATH=$PATH" "HOME=$HOME" "XDG_CACHE_HOME=$work/cache" \
        ${DOCKER_HOST:+"DOCKER_HOST=$DOCKER_HOST"} \
        act "$event" --workflows ".github/workflows/$workflow" --eventpath "$work/$payload" \
        --platform self-hosted=-self-hosted --platform prod-db=-self-hosted \
        --platform staging=-self-hosted \
        --local-repository "datadouble/datadouble@$version=$checkout" \
        --env DATADOUBLE_BOUNDARY=inside --env RUNNER_ENVIRONMENT=self-hosted \
        --env GITHUB_RUN_ID="$RANDOM" --secret-file "$secrets"
}

run workflow_dispatch datadouble-shop-build.yml manual.json
run workflow_dispatch datadouble-shop-promote.yml manual.json
run workflow_dispatch datadouble-shop-fetch.yml manual.json
run pull_request datadouble-shop-provision.yml opened.json

copies() {
    docker run --rm --user 999:999 --volume "$base:$base" --volume "$PWD:$PWD" --workdir "$PWD" \
        "$image" copies --spec datadouble/shop.yml
}
expect() {
    local listed
    listed=$(copies)
    echo "$listed"
    if ! grep -q "^copies: $1 copies recorded" <<< "$listed"; then
        echo "expected $1 copies" >&2
        exit 1
    fi
}

step "The copy pull request 1 got"
expect 1
run pull_request datadouble-shop-release.yml closed.json
step "Released when it closed"
expect 0
run workflow_dispatch datadouble-shop-prune-production.yml manual.json
run workflow_dispatch datadouble-shop-prune-non-production.yml manual.json
step "Done: every job ran green"
