# Godot demo

A small Godot project with a public Message of the Day, Haiven chat, and an inventory fed by the player's
active Haiven *item* entitlements. It is a complete Godot project with
its own scene and the Haiven GDScript addon.

## Set up the demo

1. Install **Godot 4.5.1**.
2. Clone this repository or extract the source ZIP from
   [Releases](https://github.com/haiven-dev/haiven-sdk-godot-demo/releases).
3. If the demo is under `demos/godot` in an SDK checkout, run
   `python3 demos/godot/install_addon.py` from the checkout root before
   opening the project. The standalone checkout and ZIP include
   `addons/haiven`.
4. In Godot Project Manager, select **Import** and choose `project.godot`
   from the demo folder. Open the project and press **F5** to run it.

The scene opens offline without configuration. See [Connecting to Haiven](#connecting-to-haiven)
for live chat and inventory.

## What is here

The pieces follow the injection points Haiven was asked to show in Godot:

| Piece | File | What it does |
|---|---|---|
| Autoload singleton | `haiven_demo.gd` (autoload `HaivenDemo`) | Owns one `HaivenSession` over `WebSocketPeer`, polled from `_process`. Reads entitlements on `auth.success` and on each `entitlements.updated` push. |
| Message of the Day | packaged `haiven_motd_panel.tscn` | Starts the public REST read before the access-token gate, then presents normalized loading, absent, present, and failure states in editor-authored controls. Safe HTTPS actions are handed back to the host. |
| Chat box | `demo.gd` / `demo.tscn` | An editor-authored `LineEdit` whose `text_submitted` sends to the channel, and a log where each sent message keeps one line. |
| Presentation theme | `demo_theme.tres` | Demo-only semantic type variations (`HaivenDemoTitle`, `HaivenDemoChatLog`, `HaivenDemoChatInput`, and `HaivenDemoInventory`) that a designer can restyle without changing behavior code. |
| Chat lines | `demo_chat.gd` | Turns the addon's `HaivenChat` outbox into log lines: each sent message keeps one line, keyed by its client message id, that moves through sending, accepted, held, not shown, refused, or unconfirmed when the socket closes. Other players' messages on the channel get their own line. |
| Inventory manager | `inventory_manager.gd`, `demo_item.gd` | An array of item Resources, one per active `item` entitlement. Subscriptions and founder status are not items. |
| REST transport | packaged `HaivenHttpTransport` | The addon's production `HTTPRequest` host: bounded responses, HTTPS-only outside explicit loopback tests, no credential-bearing redirects, and the `request`/`url` Callables `HaivenRestApi` takes. |
| Offline quickstart | `offline_quickstart.gd` | Credentials-free sample wiring session, chat, rewards, and analytics through injected in-memory seams. |
| Sign in with Haiven | `demo_sign_in.gd`, `loopback_callback.gd` | The addon's PKCE game-login handoff (`HaivenHandoff`). The registered redirect is `http://127.0.0.1:47615/haiven/callback`, the loopback already registered for the SBX game integration. An ephemeral loopback receives the one-use code, and that address is sent only as `delivery_uri`. The finite sign-in states and product copy are from `docs/game-auth-handoff.md`. The addon has no loopback listener, so the demo carries one. |

The outbox itself is the addon's `HaivenChat`, the same one a game uses: it
tracks each send through its moderation outcome and resends unconfirmed
messages under the same client message id when a new session is attached. When
the credential ends, the demo forgets that outbox and clears the inventory,
and drops an entitlements read still in flight, so the next sign-in cannot
send or show the previous account's or be signed out by that read.

The complete visual hierarchy is editable in `demo.tscn`; `demo.gd` only binds
the named chat, inventory, and packaged MOTD controls to
runtime behavior. `demo_theme.tres` is deliberately a demo resource, not part
of the deterministic source-only addon ZIP. It uses stock Godot controls and
contains no third-party artwork, font, or imported asset.

## Haiven versioning

The Haiven SDK and haiven-sdk-godot follow semver. A feature of the Godot target
ships in the shared major.minor release, in parity with the other target SDKs.
A patch of haiven-sdk-godot is a fix and can ship on its own.

This demo normally publishes that same major.minor but does not follow semver.
A feature or a breaking change unique to this demo can ship as a patch, which
leaves the Haiven SDK and haiven-sdk-godot unchanged. This follows Haiven's
accepted SDK versioning decision.

## Connecting to Haiven

After [setting up the demo](#set-up-the-demo), run the offline smoke test from
the folder that contains `project.godot`.

```sh
godot --headless --path . --import
godot --headless --path . --script offline_quickstart.gd
```

On success, it prints `HAIVEN_TEST_PASS readiness 12`. For a live connection,
configure the integration and launch the editor from the same environment.

1. Set these in the environment that launches Godot. None of them is written
   to disk:

   | Variable | Example |
   |---|---|
   | `HAIVEN_DEMO_BASE_URL` | `https://<api host>/v0` |
   | `HAIVEN_DEMO_REALTIME_URL` | `wss://<api host>/v0/ws` |
   | `HAIVEN_DEMO_APP_ID` | the integration's app id |
   | `HAIVEN_DEMO_INTEGRATION_ID` | the game's public launch integration id. Optional; sent as `integration_id` on `GET /motd`. It is not the app id, and the two differ in Boss Room. With it unset the demo skips the Message of the Day and says so in the log |
   | `HAIVEN_DEMO_CHANNEL_ID` | the chat channel to show |

   Then either sign in from the game (below) or use the shortcut:

   | Variable | Default | Effect |
   |---|---|---|
   | `HAIVEN_DEMO_SIGN_IN_URL` | unset | Haiven's frontend game sign-in page. It is never inferred from the API URL. SBX uses `https://sbx.haiven.gg/connect/game`; STG uses `https://haiven.gg/connect/game` |
   | `HAIVEN_DEMO_INTEGRATION_ID` | unset | The game integration the sign-in belongs to |
   | `HAIVEN_DEMO_REDIRECT_URI` | `http://127.0.0.1:47615/haiven/callback` | The registered browser callback. This is the loopback already registered for the SBX game integration. Boss Room uses the same URI. The game does not listen on this port. Set this to replace the default. It must be in the integration's `allowedRedirectUris` exactly |
   | `HAIVEN_DEMO_ACCESS_TOKEN` | unset | A player access token. When set, the demo starts signed in and never opens a browser |

2. Open `project.godot` in Godot 4.5.1 from that environment and run it. With a variable
   missing, the log says which one and the demo stays offline.

### Sign in with Haiven

With no `HAIVEN_DEMO_ACCESS_TOKEN`, the demo starts signed out, still showing
the public Message of the Day. Pressing **Continue with Haiven**, above the
chat log:

1. Binds `127.0.0.1` on a port the operating system chooses
   (`loopback_callback.gd`). A failed bind stops here instead of after the
   player signs in. Port 47616 is not bound.
2. Opens the system browser (`OS.shell_open`) on the sign-in page with the
   addon's PKCE authorization query (`HaivenHandoff.begin_login`): the
   integration, `completion=redirect`, the registered redirect
   `http://127.0.0.1:47615/haiven/callback`, a
   one-use `state`, an S256 challenge, and `delivery_uri` set to
   `http://127.0.0.1:<port>/haiven/callback`. `delivery_uri` is not sent to
   the API. The page refuses any other delivery address and issues no code.
3. Receives the browser on that ephemeral port, answers it with a static
   "return to the game" page, and hands the code to `HaivenHandoff.complete`
   against the registered redirect. That checks the redirect and
   state, then exchanges the one-use code at
   `<HAIVEN_DEMO_BASE_URL>/auth/handoff/exchange`.
4. Connects chat and REST with the returned bearer, held in memory only.

Failures are finite states, each with a retry button: cancelled
(`error=access_denied`), link expired (no redirect within 30 minutes, or the code
was refused), unavailable (`503`), port in use, and failed. When the
credential's expiry passes, or the server proves it invalid (REST `401`,
WebSocket `auth.expired`, a `1008 unauthorized` or `credential_revoked` close),
the demo disconnects and asks the player to sign in again. There is no
background refresh. The token, the code, and the verifier are never logged,
shown, or written to disk. Loopback needs sockets, so a Web export would use an
HTTPS callback instead.

The game integration you sign in through must list
`http://127.0.0.1:47615/haiven/callback` in its `allowedRedirectUris`. Ask
Haiven to register it if your integration does not have it yet. This demo does not add `http://127.0.0.1:47616/haiven/callback` and does
not bind 47615 or 47616. The ephemeral loopback is not registered. Boss Room
listens on 47615 only while it is signing in, and Lyra uses 28823, so this
demo can run beside them.

For SBX, a test player needs only an SBX Haiven account: the sign-in page at
`https://sbx.haiven.gg/connect/game` signs the player in or registers them,
and the demo receives the credential itself. There is no token to copy by hand.

## Building a standalone player

`export_presets.cfg` holds one runnable desktop preset per
`haiven sdk demo build` target. It holds no secrets, signing identities, or
machine paths:

| Preset | Target | Default output (from the repository root) |
|---|---|---|
| `Linux` | `linux64` | `build/godot-demo/linux64/HaivenGodotDemo.x86_64` and `.pck` |
| `Windows Desktop` | `win64` | `build/godot-demo/win64/HaivenGodotDemo.exe` and `.pck` |
| `macOS` | `osx` | `build/godot-demo/osx/HaivenGodotDemo.zip` (universal `.app`) |

Exporting needs the official Godot 4.5.1 export templates. The editor installs
them from **Editor > Manage Export Templates**; they land in Godot's user data
folder. Run from the folder that contains `project.godot`:

```sh
godot --headless --path . --import
mkdir -p build/godot-demo/linux64
godot --headless --path . --export-release "Linux" "$PWD/build/godot-demo/linux64/HaivenGodotDemo.x86_64"
```

Use `"Windows Desktop"` or `"macOS"` with their paths for the other targets.
Create the output folder first. Pass an absolute output path, because a
relative one resolves against the project folder. If you leave the path out,
the preset's `export_path` writes the output shown in the table, under the
repository's gitignored `build/`.

Each preset exports every resource except `demo_test.gd` and
`offline_quickstart.gd`. The PCK sits beside the executable instead of being
embedded in it. The Windows preset leaves code signing off. The macOS preset
ad-hoc signs with Godot's built-in signer and does not notarize, so Gatekeeper
asks the player to approve the first launch. Real signing and notarization
credentials belong in the exporting machine's editor settings, not in this
file. Universal macOS exports need ETC2/ASTC texture import, which
`project.godot` enables.

The player reads the same `HAIVEN_DEMO_*` environment variables as the editor
run. Without them it starts offline and logs which one is missing.

## Verification

| Check | How | Evidence |
|---|---|---|
| Demo behaves | `make check-godot` (part of `make check`). It copies this project and the addon into a temporary folder, imports it, and runs `demo_test.gd` headless | `HAIVEN_TEST_PASS demo 30` over a fake socket and REST request plus the editor-authored hierarchy, submit/focus wiring, behavior properties, semantic Theme hooks, public MOTD states, keyed lines, and inventory list |
| Package consumer wires | `make check-godot-ci` | Builds and installs the deterministic addon ZIP, clean-imports it, exercises the packaged HTTP transport against an ephemeral loopback server, then runs `offline_quickstart.gd` with no credentials |
| Export presets load | `make check-godot`, stage `demo-export` | Runs `--export-release` for each preset. With templates installed, each preset must write its player. Without them, missing templates must be the only configuration error, so a broken or incomplete preset still fails |
| Scene runs | `godot --headless --path <staged demo> --quit-after 60` | Exits 0 with no engine errors or warnings, with the autoload loaded |
| Sign-in behaves | `make check-godot` | `HAIVEN_TEST_PASS demo_sign_in 38`: the loopback listener over a real `127.0.0.1` socket (exact redirect, 404 for other paths, a `no-store` page that echoes nothing, failed bind), the default registered redirect `http://127.0.0.1:47615/haiven/callback` for SBX and a local sign-in page, an explicit `HAIVEN_DEMO_REDIRECT_URI` override, an ephemeral `delivery_uri` that is not the registered redirect, and the sign-in states with the browser and exchange injected (success, cancel, wait timeout, expiry, REST `401` vs `403`, `credential_revoked`, `auth.expired` re-auth, a later sign-in does not resend the previous account's chat, and a late entitlements response does not refill inventory or sign the next account out) |
| Against a live server | The steps above, against sbx or stg | Not automated: it needs a browser sign-in, a channel, and an item entitlement, and the redirect registered on the integration |

## License

Haiven's source in this repository, the demo and the `addons/haiven` addon, is
licensed under the Apache License, Version 2.0 (SPDX `Apache-2.0`). The terms
are in `LICENSE`, and the addon carries the same text at
`addons/haiven/LICENSE`. Contributions are accepted under that license.

Godot Engine is not part of this repository; it has its own MIT license.

<!-- features:start (generated by codegen/features.py; do not edit) -->

### Feature coverage

This table summarizes the SDK used by this demo. The demo exercises the features described in its setup and examples.

| Family | Godot |
|---|:---:|
| Envelope | ~ |
| Session lifecycle | ~ |
| Request recovery | ✅ |
| Open vocabularies | ~ |
| REST | ○ |
| Game login handoff | ○ |
| P2P sessions | ○ |
| Credential lifecycle | ~ |
| API surface | ✅ |
| Product | ~ |
| Developer experience | ~ |

✅ shipped · `↑` inherited from the language SDK this target ships, proven only in that SDK's runner and not inside the engine · `~` partial · `—` absent · `○` not yet proven by any scenario · `⊘` not applicable. A family cell is ✅ only when every counted row is ✅, and `↑` when every counted row is ✅ or `↑`; `MAY` requirements and rows marked optional are not counted. Every row: the full Haiven SDK feature matrix.

<!-- features:end -->
