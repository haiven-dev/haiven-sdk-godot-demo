# Godot demo

A small Godot project with a public Message of the Day, Haiven chat, and an inventory fed by the player's
active Haiven *item* entitlements. Godot has no first-party sample game to
integrate into (decision 0001), so this demo is a complete scene, kept in the
repository.

**Supported runtime:** Godot 4.5.1, the SDK's pinned version, using the
GDScript addon from `sdks/godot/gdscript/addons/haiven`. Desktop and editor.
Web exports would need the browser's HTTP rules (CORS) for the REST read.

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

The outbox itself is the addon's `HaivenChat`, the same one a game uses: it
tracks each send through its moderation outcome and resends unconfirmed
messages under the same client message id when a new session is attached.

The complete visual hierarchy is editable in `demo.tscn`; `demo.gd` only binds
the named chat, inventory, and packaged MOTD controls to
runtime behavior. `demo_theme.tres` is deliberately a demo resource, not part
of the deterministic source-only addon ZIP. It uses stock Godot controls and
contains no third-party artwork, font, or imported asset.

## Running it

For a no-network smoke test that uses no secrets, install the addon as below and
run:

```sh
godot --headless --path demos/godot --script offline_quickstart.gd
```

It prints `HAIVEN_TEST_PASS readiness 12`. The normal interactive demo uses a
live WebSocket and REST API:

1. Copy the addon in. The copy is gitignored, so the SDK keeps one source:

   ```sh
   python3 demos/godot/install_addon.py
   ```

2. Set these in the environment that launches Godot. None of them is written
   to disk:

   | Variable | Example |
   |---|---|
   | `HAIVEN_DEMO_BASE_URL` | `https://<api host>/v0` |
   | `HAIVEN_DEMO_REALTIME_URL` | `wss://<api host>/v0/ws` |
   | `HAIVEN_DEMO_APP_ID` | the integration's app id |
   | `HAIVEN_DEMO_CHANNEL_ID` | the chat channel to show |
   | `HAIVEN_DEMO_ACCESS_TOKEN` | a player access token |

3. Open `demos/godot/project.godot` in Godot 4.5.1 and run it. With a variable
   missing, the log says which one and the demo stays offline.

## Verification

| Check | How | Evidence |
|---|---|---|
| Demo behaves | `make check-godot` (part of `make check`). It copies this project and the addon into a temporary folder, imports it, and runs `demo_test.gd` headless | `HAIVEN_TEST_PASS demo 30` over a fake socket and REST request plus the editor-authored hierarchy, submit/focus wiring, behavior properties, semantic Theme hooks, public MOTD states, keyed lines, and inventory list |
| Package consumer wires | `make check-godot-ci` | Builds and installs the deterministic addon ZIP, clean-imports it, exercises the packaged HTTP transport against an ephemeral loopback server, then runs `offline_quickstart.gd` with no credentials |
| Scene runs | `godot --headless --path <staged demo> --quit-after 60` | Exits 0 with no engine errors or warnings, with the autoload loaded |
| Against a live server | The steps above, against stg | Not automated: it needs a stg channel, a player token and an item entitlement |

## Haiven versioning

haiven-sdk and haiven-sdk-godot follow semver. A feature of the Godot target ships in the shared major.minor release, in parity with the other target SDKs. A patch of haiven-sdk-godot is a fix and can ship on its own.

This demo, haiven-sdk-godot-demo, publishes that same major.minor and does not follow semver. A feature that shows part of the platform in this demo can be introduced in a patch. That patch leaves haiven-sdk and haiven-sdk-godot unchanged.

The proposal is [haiven-docs ADR 0051](https://github.com/haiven-dev/haiven-docs/blob/docs/adr-0051-major-minor-lockstep/decisions/0051-major-minor-lockstep.md).
