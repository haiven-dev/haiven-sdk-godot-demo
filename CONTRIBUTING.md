# Contributing

Contributions are welcome. This repository is public. Bug reports, fixes,
and documentation improvements are all useful.

The Godot project is at the repository root. The addon already ships in
`addons/haiven`.

## Issues

Open a GitHub issue for a bug, a question about behavior, or a change you
want to discuss before writing it. Search open issues first.

Include the Godot version and the steps that show the problem. Do not
paste access tokens, passwords, or private endpoints.

## Pull requests

1. Fork the repository and branch from `sdk-dev`.
2. Keep the change focused.
3. Use a [Conventional Commits](https://www.conventionalcommits.org/)
   subject:

   `type(scope): subject`

   `type` is one of `feat`, `fix`, `docs`, `deps`, `style`, `refactor`,
   `perf`, `test`, `build`, `ci`, `chore`, or `revert`. `scope` is
   optional.
4. Open the pull request against `sdk-dev`. Say what changed and how you
   checked it. `main` changes only through the maintainers' promotion and
   release pull requests.

Do not commit access tokens, passwords, private endpoints, or local
credentials. Do not replace `addons/haiven` with files from outside this
repository unless the pull request is explicitly updating that addon and
says where the copy came from.

## Checks

Godot 4.5.1 is the version this demo is written for. From the repository
root, with no credentials:

```sh
godot --headless --path . --script offline_quickstart.gd
```

Success prints `HAIVEN_TEST_PASS readiness 12` and exits 0.
