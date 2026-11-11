# Godot demo

A small Godot project with a public Message of the Day, Haiven chat, and an inventory fed by the player's
active Haiven *item* entitlements. Godot has no first-party sample game to
integrate into (decision 0001), so this demo is a complete scene, kept in the
repository.

**Supported runtime:** Godot 4.5.1. The GDScript addon ships in this
repository at `addons/haiven`. Desktop and editor. Web exports would need the
browser's HTTP rules (CORS) for the REST read.

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

For a no-network smoke test that uses no secrets, from this repository's root:

```sh
godot --headless --path . --script offline_quickstart.gd
```

It prints `HAIVEN_TEST_PASS readiness 12`. The addon is already at
`addons/haiven`. `python3 install_addon.py` keeps that copy. Set
`HAIVEN_SDK_GODOT` to a `haiven-sdk-godot` checkout only when replacing it;
a missing checkout does not delete the packaged addon.

The normal interactive demo uses a live WebSocket and REST API:

1. Set these in the environment that launches Godot. None of them is written
   to disk:

   | Variable | Example |
   |---|---|
   | `HAIVEN_DEMO_BASE_URL` | `https://<api host>/v0` |
   | `HAIVEN_DEMO_REALTIME_URL` | `wss://<api host>/v0/ws` |
   | `HAIVEN_DEMO_APP_ID` | the integration's app id |
   | `HAIVEN_DEMO_CHANNEL_ID` | the chat channel to show |
   | `HAIVEN_DEMO_ACCESS_TOKEN` | a player access token |

2. Open `project.godot` in Godot 4.5.1 and run it. With a variable missing,
   the log says which one and the demo stays offline.

## Verification

From the repository root, with Godot 4.5.1:

```sh
python3 -m unittest test_install_addon.py
python3 ci/check_editor.py
```

`ci/check_editor.py` runs `offline_quickstart.gd` (`HAIVEN_TEST_PASS readiness 12`)
and `demo_test.gd` (`HAIVEN_TEST_PASS demo 30`) with no credentials.
`.github/workflows/build.yml` runs both on pull requests and on a `v*` tag.
It does not publish a release. A live server is not part of that build.
