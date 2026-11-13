# Releasing haiven-sdk-godot-demo

This file is for maintainers. It covers how work moves from `sdk-dev` to
`main` and how a release is cut.

## Branches: `sdk-dev` and `main`

- Topic branches carry unready work and update by rebase.
- `sdk-dev` takes ready work. Pull requests into it are squash-merged, and
  their titles use [Conventional Commits](https://www.conventionalcommits.org/)
  because the title becomes the commit.
- `main` is released. It changes through the promotion pull request and the
  release pull request.

## Promoting `sdk-dev` to `main`

The `Promotion PR` workflow (`.github/workflows/promotion-pr.yml`) keeps one
pull request open from `sdk-dev` into `main`, titled
`chore: promote sdk-dev into main`. It runs on every push to either branch and
can also be started by hand from the Actions tab. Its description lists every
commit `sdk-dev` carries that `main` lacks, grouped as breaking changes,
features, bug fixes, and other changes. Only the block between the
`promotion-pr` markers is regenerated, so reviewer notes outside it are kept.
When `sdk-dev` has no commits that `main` lacks, the workflow does nothing.
A push runs the workflow file on the branch it lands on, so pushes to `sdk-dev`
start it only after `sdk-dev` contains `promotion-pr.yml`; until then, pushes
to `main` and manual runs keep the pull request current.

The workflow uses
[`haiven-dev/haiven-actions/actions/promotion-pr`](https://github.com/haiven-dev/haiven-actions/blob/main/docs/promotion-pr.md),
pinned to a reviewed commit. It never pushes, merges, versions, tags, or
releases. It opens the pull request with a `haiven-release` GitHub App token,
so the `Build` checks run on it.

Review the promotion pull request like any other, then merge it with a
**merge commit**. Do not squash or rebase it: a merge commit keeps each
`sdk-dev` commit on `main`, so Release Please can read their subjects and the
next promotion lists only newer work.

## Releases

Release Please (`.github/workflows/release-please.yml`) runs on `main` as the
`haiven-release` GitHub App. After a promotion lands, it opens a separate
release pull request that updates `CHANGELOG.md` and
`.release-please-manifest.json`. Merging that pull request publishes the
`v<version>` tag and GitHub release.

The demo normally follows the shared SDK major.minor line. A feature or
breaking change unique to this demo may ship as a patch. Use a `Release-As:`
footer in a commit on `sdk-dev` when the default bump would not express that.

The demo version is stored in `.release-please-manifest.json`. The checked-in
`addons/haiven` directory is a copy of the Godot SDK addon, and
`install_addon.py` replaces it from an SDK checkout. Its `plugin.cfg` keeps the
SDK's version and is not a demo release file.

## After every release

Merge `main` back into `sdk-dev` with a merge commit, through a pull request
from `main` into `sdk-dev`. That brings the release commit, changelog, and
manifest onto `sdk-dev`, so the next promotion starts clean. Do not reset or
force-push `sdk-dev`.
