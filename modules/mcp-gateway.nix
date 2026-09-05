# home-manager module: services.mcpGateway
#
# WHAT THIS DOES
# Runs ONE shared instance of your MCP servers behind sparfenyuk/mcp-proxy — a
# launchd USER agent bound to a loopback host:port (default 127.0.0.1:8096),
# started at login (RunAtLoad) and kept alive. Point every MCP client (Claude
# Code, Claude Desktop, VS Code, a CLI) at the resulting HTTP endpoints instead
# of each spawning its own stdio copy of the same server: one shared process,
# one cache, no duplicate spawns, always up.
#
# WHAT THIS IS NOT
# This module does NOT generate per-server Nix packaging (pinned store-path
# commands, provider-specific option schemas, etc.) — that's the job of
# natsukium/mcp-servers-nix, which this module happily sits on top of if you
# want it (see the README). `services.mcpGateway.servers` is a deliberately
# thin `{ command; args; env; }` shape: point it at ANY MCP server binary,
# whether that's a store path from mcp-servers-nix, a plain `npx`/`uvx`
# launcher, or your own script. This module owns exactly one thing: hosting
# whatever servers you hand it behind a single mcp-proxy launchd agent.
#
# REQUIREMENT: a launchd USER (GUI) agent lives in the `gui/<uid>` domain,
# which only exists while that uid has an active GUI login — so the account
# running `home-manager switch` must be the one logged into the Mac.
#
# SECRETS: `servers.<name>.env` values land verbatim in the generated mcp-proxy
# JSON config, which lives in the world-readable /nix/store — so this option
# is for non-secret configuration only. For a secret an MCP server needs at
# launch (an API key, a database URI), wrap the real command in a script that
# fetches the value at RUN time (e.g. from the macOS Keychain via
# `/usr/bin/security find-generic-password`) and point `command` at that
# wrapper instead — see the README's "secrets" section for the pattern.
#
# macOS-ONLY: gated on stdenv.isDarwin, so enabling it on a Linux host is a
# clean no-op (safe for mixed nix-darwin + NixOS fleets).
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.mcpGateway;

  jsonFormat = pkgs.formats.json { };

  # SERVER SIDE: a {mcpServers:{name:{command,args,env}}} JSON that mcp-proxy
  # consumes via --named-server-config. `env` is only emitted when non-empty,
  # matching mcp-proxy's own schema.
  gatewayConfigFile = jsonFormat.generate "mcp-gateway.json" {
    mcpServers = lib.mapAttrs (
      _name: server:
      {
        inherit (server) command args;
      }
      // lib.optionalAttrs (server.env != { }) { inherit (server) env; }
    ) cfg.servers;
  };

  # Gateway URL for a server (Streamable HTTP — the current MCP transport
  # standard). mcp-proxy ALSO serves the legacy `/sse` path at the same
  # prefix for SSE-only clients; swap the trailing segment yourself if a
  # client needs that instead. Single source of truth for every consumer.
  endpointFor = name: "http://${cfg.host}:${toString cfg.port}/servers/${name}/mcp";
in
{
  options.services.mcpGateway = {
    enable = lib.mkEnableOption "the localhost MCP gateway (a sparfenyuk mcp-proxy launchd user agent hosting your MCP servers over HTTP)";

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = ''
        Loopback address the gateway's mcp-proxy binds. Keep this on loopback
        unless you have your own reason (and your own auth/firewalling) to
        expose it further — mcp-proxy does no authentication itself.
      '';
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8096;
      description = "TCP port the gateway's mcp-proxy binds on `host`.";
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.mcp-proxy;
      defaultText = lib.literalExpression "pkgs.mcp-proxy";
      description = "The `mcp-proxy` package providing the gateway binary.";
    };

    logFile = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/Library/Logs/mcp-gateway.log";
      defaultText = lib.literalExpression ''"''${config.home.homeDirectory}/Library/Logs/mcp-gateway.log"'';
      description = "Path the launchd agent's stdout+stderr are appended to.";
    };

    extraPath = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      example = lib.literalExpression "[ pkgs.nodejs pkgs.uv ]";
      description = ''
        Packages prepended onto the launchd agent's `PATH`, ahead of
        `/usr/bin:/bin`. launchd agents start with a minimal PATH, so any
        server command resolved by *name* (an `npx`/`uvx` launcher, say,
        rather than an absolute store path) needs its runtime here.
      '';
    };

    servers = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            command = lib.mkOption {
              type = lib.types.str;
              description = ''
                Executable to launch this MCP server. An absolute path (a
                store path, or the output of `lib.getExe'`) is the most
                robust choice under launchd's minimal PATH; a bare name
                (`"npx"`) also works if it resolves via `extraPath`.
              '';
            };
            args = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "Arguments passed to `command`.";
            };
            env = lib.mkOption {
              type = lib.types.attrsOf lib.types.str;
              default = { };
              description = ''
                Extra environment variables for this server's process.
                These land in the generated JSON config (and therefore the
                Nix store) in plaintext — non-secret configuration only. For
                a value that must stay secret, wrap `command` in a script
                that fetches it at run time instead of passing it here (see
                the README).
              '';
            };
          };
        }
      );
      default = { };
      example = lib.literalExpression ''
        {
          # A packaged server, e.g. from natsukium/mcp-servers-nix's mkConfig.
          fetch = {
            command = lib.getExe' pkgs.mcp-server-fetch "mcp-server-fetch";
          };
          # A plain npx-launched server — needs `pkgs.nodejs` in `extraPath`.
          memory = {
            command = "npx";
            args = [ "-y" "@modelcontextprotocol/server-memory" ];
          };
        }
      '';
      description = ''
        The MCP servers this gateway hosts, keyed by name. Each becomes a
        named server inside one shared mcp-proxy process, reachable at
        `http://<host>:<port>/servers/<name>/mcp`. Empty by default — this
        module ships no servers of its own; you supply the catalog.
      '';
    };

    endpoints = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      readOnly = true;
      default = lib.mapAttrs (name: _: endpointFor name) cfg.servers;
      defaultText = lib.literalExpression "derived from `servers`";
      description = ''
        Read-only map of hosted server name -> its Streamable-HTTP (`/mcp`)
        gateway URL. Computed once from `servers` + `host` + `port`; wire
        these into your MCP clients' own config (`programs.claude-code`,
        a VS Code `mcp.json`, etc.) however suits your setup — this module
        does not write client config itself.
      '';
    };
  };

  # macOS-only: a clean no-op on Linux hosts.
  config = lib.mkIf (cfg.enable && pkgs.stdenv.isDarwin) {
    launchd.agents.mcp-gateway = {
      enable = true;
      config = {
        ProgramArguments = [
          (lib.getExe' cfg.package "mcp-proxy")
          "--host"
          cfg.host
          "--port"
          (toString cfg.port)
          "--named-server-config"
          "${gatewayConfigFile}"
        ];
        RunAtLoad = true;
        KeepAlive = true;
        EnvironmentVariables.PATH = lib.makeBinPath cfg.extraPath + ":/usr/bin:/bin";
        StandardOutPath = cfg.logFile;
        StandardErrorPath = cfg.logFile;
      };
    };
  };
}
