# Contributing to haiven-sdk-godot-demo

Haiven's engineering standards apply to this repository. Read them first:

- [Contribution standard](https://github.com/haiven-dev/haiven-docs/blob/main/standards/contributing.md)
  covers commits, pull requests, review, and releases.
- [Documentation standard](https://github.com/haiven-dev/haiven-docs/blob/main/standards/documentation.md)
  covers repository documentation.

This file records only what this Godot demo does differently.

## Branches: `sdk-dev` and `main`

- Topic branches carry unready work and update by rebase.
- `sdk-dev` takes ready work. Pull requests into it are squash-merged, and
  their titles use Conventional Commits because the title becomes the commit.
- `main` is released. The promotion workflow opens a reviewed pull request
  from the exact `sdk-dev` revision that is ready to release.

### Promoting `sdk-dev` to `main`

Run the `promote sdk-dev` workflow from `main` and enter the full current
`sdk-dev` SHA. It refuses a moved, empty, or divergent range, publishes a
disposable `promote/sdk-dev-<sha>` branch, and opens the promotion pull request.
It never merges or resets `sdk-dev`.

The generated pull request is titled `chore: promote sdk-dev to main`. Its
description carries each commit in a `BEGIN_COMMIT_OVERRIDE` block so Release
Please can reconstruct the changelog after the promotion is squash-merged.
Review and squash-merge that pull request; do not merge the branches locally.

### After every release

After the Release Please pull request has merged, reset `sdk-dev` to the new
`main` with a lease guarded by the exact SHA that was promoted:

```sh
git fetch origin
git push --force-with-lease=sdk-dev:<promoted-sdk-dev-sha> origin origin/main:refs/heads/sdk-dev
```

If newer commits reached `sdk-dev`, the lease refuses the reset. Rebase only
those commits onto `origin/main`, then publish them with a lease guarded by the
current remote `sdk-dev` SHA.

## Releases

Release Please runs on `main` as the org-owned `haiven-release` GitHub App.
After a promotion, it opens a separately reviewed version and changelog pull
request. Merging that pull request publishes the `v<version>` tag and GitHub
release.

The demo normally follows the shared SDK major.minor line. A feature or
breaking change unique to this demo may ship as a patch; use a `Release-As:`
footer when Release Please's default bump would not express that exception.

The demo version is stored in `.release-please-manifest.json`. The checked-in
`addons/haiven` directory is a copy of the Godot SDK, and `install_addon.py`
replaces it from the SDK checkout. Its `plugin.cfg` therefore keeps the SDK's
version and is not a demo release file.

## Checks

Godot 4.5.1 is the supported runtime. To verify that the demo installs a Godot
SDK checkout, run:

```sh
HAIVEN_SDK_GODOT=/absolute/path/to/haiven-sdk-godot python3 test_install_addon.py
```

For the headless demo checks, use the commands listed in `README.md` from the
matching aggregate `haiven-sdk` checkout.
