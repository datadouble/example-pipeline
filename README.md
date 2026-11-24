# example-pipeline

A complete [Datadouble](https://datadouble.tightlinesoftware.com/) pipeline
for a small shop database, on both sides of the production boundary, in
GitHub Actions. Everything here except `source/` and `scripts/` is what a
team commits.

```
git clone https://github.com/datadouble/example-pipeline
cd example-pipeline
make demo
```

`make demo` runs every job on your machine, as the team's runners would (see
[Running it](#running-it)).

## The files

| File | What it is |
|---|---|
| `datadouble/shop.yml` | The spec: the first fifty customers and their orders, and every product, names and emails replaced, signed, promoted to an export store, and one copy per pull request |
| `datadouble/catalog.lock` | The source's catalog when the spec was written, with the extensions it uses; a new table, column or extension fails the plan until someone decides what to do with it (strict mode) |
| `.github/workflows/datadouble-shop-*.yml` | The jobs, written by `datadouble ci init`, never edited by hand |
| `source/shop.sql` | The demo's throwaway source |
| `scripts/demo.sh` | Runs the whole pipeline locally |

The workflows came from two commands, one per side of the boundary:

```
datadouble ci init --system github-actions --job build,promote,prune \
    --spec datadouble/shop.yml --runner prod-db --work /var/tmp/example-pipeline/work
datadouble ci init --system github-actions --job fetch,provision,release,prune,activate \
    --spec datadouble/shop.yml --runner staging
```

| Workflow | Side | Started by |
|---|---|---|
| build | production, runner `prod-db` | Mondays at 02:00 UTC, or by hand |
| promote | production | a successful build |
| prune (production) | production | daily |
| fetch | non-production, runner `staging` | every 15 minutes |
| provision | non-production | a pull request opening: one copy for it |
| release | non-production | the pull request closing, and a daily sweep |
| prune (non-production) | non-production | daily |
| activate | non-production | by hand, to roll back |

## The extension

The shop's `product` table stores embeddings in a pgvector `vector` column,
so the source uses the `vector` extension. The lock records it at the
source's version (0.8.7), and the spec's `source.image` names the pgvector
image, built on the same PostgreSQL release as the source, for the working
databases. Without that line the build would use the official
`postgres:18.7-trixie` image, which has no pgvector, and stop before reading
the source:

```
error: the working image lacks 1 requirement(s) of the source; name an image that has them in source.image, or leave them out with source.omit
  source.image: extension vector is not in the working image
```

If the DBAs upgrade pgvector on the source, strict mode stops the next build
until someone moves the image to the matching release and re-locks. See
[Extensions, plugins and modules](https://datadouble.tightlinesoftware.com/using/source-requirements/).

## To use it for real

- **Runners.** A self-hosted runner labelled `prod-db` inside the production
  boundary, and one labelled `staging` outside it, each with Docker and the
  spec's directories under `/var/tmp/example-pipeline` owned by `999:999`.
  The operator marks the production runner inside the boundary by adding
  `DATADOUBLE_BOUNDARY=inside` to its `.env`; nothing else may.
- **Secrets.** `SHOP_SOURCE_DSN`, `SHOP_COSIGN_KEY`, `COSIGN_PASSWORD` and
  `SHOP_COSIGN_PUB` for the production runner's jobs; only `SHOP_COSIGN_PUB`
  for the non-production ones.
- **Enable the workflows.** They are disabled in this repository, which has no
  runners, so their schedules do not queue jobs nobody can run.

## Running it

`make demo` needs Docker, git and make. It works the same on Linux and on
macOS.

The demo runs inside a Linux container that plays the self-hosted runner
(`scripts/runner.Dockerfile`). That container has
[act](https://github.com/nektos/act) and the tools the jobs use, so you don't
install them yourself.

Inside it, the demo:

1. builds the Datadouble image from a checkout of datadouble/datadouble
   (`DATADOUBLE_CHECKOUT`, or a clone of `DATADOUBLE_REF`, `main` by default),
   and tags it as the release the workflows pin;
2. starts a throwaway PostgreSQL with pgvector;
3. makes a signing key pair;
4. runs build, promote, fetch, a pull request's copy, its release, and both
   prunes, with act running each job as a self-hosted runner does.

Everything it makes goes under `/var/tmp/example-pipeline` on the Docker host,
and it removes all of it when it finishes. On macOS, the Docker host is
Docker's Linux virtual machine, not your Mac.

This repository's own CI runs `make demo` on every push and every night.
