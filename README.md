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
| `datadouble/shop.yml` | The spec: the first fifty customers and their orders, names and emails replaced, signed, promoted to an export store, and one copy per pull request |
| `datadouble/catalog.lock` | The source's catalog when the spec was written; a new table or column fails the plan until someone decides what to do with it (strict mode) |
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

`make demo` needs Docker, git and [act](https://github.com/nektos/act). It
builds the Datadouble image from a checkout of datadouble/datadouble
(`DATADOUBLE_CHECKOUT`, or a clone of `DATADOUBLE_REF`, `main` by default) and
tags it as the release the workflows pin; starts a throwaway PostgreSQL;
makes a signing key; then runs build, promote, fetch, a pull request's copy,
its release, and both prunes, with act running each job on this machine as a
self-hosted runner does. It removes everything it made when it finishes.

This repository's own CI runs `make demo` on every push and every night.
