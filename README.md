# nix-mcp-gateway

[![CI](https://github.com/ismailkattakath/nix-mcp-gateway/actions/workflows/ci.yml/badge.svg)](https://github.com/ismailkattakath/nix-mcp-gateway/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](./LICENSE)
[![Built with Nix](https://img.shields.io/badge/built%20with-Nix-5277C3.svg?logo=nixos&logoColor=white)](https://nixos.org)

**One shared MCP endpoint instead of N duplicate stdio spawns.** A tiny
home-manager module that runs a single `mcp-proxy` launchd user agent hosting
*your own* set of [Model Context Protocol](https://modelcontextprotocol.io)
servers over HTTP on a loopback `host:port`. Point every MCP client you use —
Claude Code, Claude Desktop, VS Code, a CLI — at the resulting endpoints
instead of each spawning its own stdio copy of the same server.

> Status: early / beta. macOS-only. Extracted from a personal nix-darwin
> fleet where it hosts a dozen-odd servers behind one gateway.

## What this is (and isn't)

This module owns exactly one thing: **the runtime gateway** — one launchd
agent, one `mcp-proxy` process, your servers behind it. It does **not**
generate per-server Nix packaging, provider-specific option schemas, or
pinned store-path commands for well-known servers — that job is already well
served by [natsukium/mcp-servers-nix](https://github.com/natsukium/mcp-servers-nix).
Use that (or a plain `npx`/`uvx` launcher, or your own script) to produce a
`command`/`args`, and hand it to this module's `servers` option — it doesn't
care where the command came from.

## Prerequisites

- **macOS** — the gateway runs as a launchd *user* (GUI) agent, which needs
  the account running `home-manager switch` to be the one logged into the
  Mac. The module is a clean no-op on Linux.
- **Nix** with flakes enabled (`experimental-features = nix-command flakes`).
- **[home-manager](https://github.com/nix-community/home-manager)**.
- `mcp-proxy` ([sparfenyuk/mcp-proxy](https://github.com/sparfenyuk/mcp-proxy))
  is available in nixpkgs as `pkgs.mcp-proxy` — no separate install needed.

## Install

```nix
{
  inputs.mcp-gateway.url = "github:ismailkattakath/nix-mcp-gateway";

  # in your home-manager modules:
  #   mcp-gateway.homeManagerModules.default
}
```

Then define your servers:

```nix
{ pkgs, lib, config, ... }:
{
  services.mcpGateway = {
    enable = true;
    extraPath = [ pkgs.nodejs ];   # npx-launched servers need Node on PATH

    servers = {
      memory = {
        command = "npx";
        args = [ "-y" "@modelcontextprotocol/server-memory" ];
      };
      fetch.command = "${pkgs.mcp-server-fetch}/bin/mcp-server-fetch";
    };
  };

  # Wire the resulting endpoints into whichever client(s) you use, e.g.
  # home-manager's claude-code module:
  programs.claude-code.mcpServers = lib.mapAttrs (_: url: {
    type = "http";
    inherit url;
  }) config.services.mcpGateway.endpoints;
}
```

See [`examples/basic.nix`](./examples/basic.nix) for a fuller catalog,
including the pattern for a server that needs a secret at launch.

## Options

| Option | Default | Description |
|---|---|---|
| `services.mcpGateway.enable` | `false` | Enable the gateway (macOS only; no-op elsewhere). |
| `services.mcpGateway.host` | `"127.0.0.1"` | Loopback address the proxy binds. |
| `services.mcpGateway.port` | `8096` | TCP port the proxy binds. |
| `services.mcpGateway.package` | `pkgs.mcp-proxy` | The `mcp-proxy` package. |
| `services.mcpGateway.servers` | `{}` | Your MCP servers: `{ command; args; env; }` each. |
| `services.mcpGateway.extraPath` | `[]` | Packages prepended onto the agent's PATH. |
| `services.mcpGateway.logFile` | `~/Library/Logs/mcp-gateway.log` | stdout+stderr log path. |
| `services.mcpGateway.endpoints` | *(computed)* | Read-only `name -> http://host:port/servers/name/mcp` map. |

`servers` ships **empty** — this module bundles no servers of its own. You
supply the catalog; see the example above and `examples/basic.nix`.

## Secrets

`servers.<name>.env` values land in the generated JSON config (and therefore
the Nix store) in plaintext — fine for non-secret configuration, wrong for an
API key or connection string. For a server that needs a secret at launch,
wrap the real command in a script that fetches it at *run* time instead
(from the macOS Keychain, `pass`, 1Password CLI, whatever you use) and point
`command` at that wrapper. See the `example-with-secret` entry in
[`examples/basic.nix`](./examples/basic.nix).

## How it works

- **Transport:** [sparfenyuk/mcp-proxy](https://github.com/sparfenyuk/mcp-proxy)
  hosts every server in `services.mcpGateway.servers` inside one process,
  each reachable at `/servers/<name>/mcp` (Streamable HTTP) — and also at
  `/servers/<name>/sse` for SSE-only clients.
- **Process model:** a launchd **user** agent (`RunAtLoad` + `KeepAlive`),
  bound to loopback — nothing listens off-box.
- **Config:** `servers` is rendered to a `{mcpServers: {name: {command, args,
  env}}}` JSON file mcp-proxy consumes via `--named-server-config`.

## When to use something else

| You want… | Use |
|---|---|
| Nix-packaged, pinned commands for well-known MCP servers | [mcp-servers-nix](https://github.com/natsukium/mcp-servers-nix) (pairs well with this — feed its output into `servers`) |
| Every client spawning its own process (no shared gateway) | your MCP client's native stdio config |
| Public/off-box exposure with auth | put your own reverse proxy + auth in front — this module only binds loopback |

## Used in production

See it wired into a real fleet in
**[kattakath/nix-config](https://github.com/kattakath/nix-config)** —
[`modules/shared/mcp.nix`](https://github.com/kattakath/nix-config/blob/main/modules/shared/mcp.nix)
hosts a dozen-odd MCP servers behind one gateway on the `macos` host.

## License

MIT © Ismail Kattakath
