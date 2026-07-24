# Example: enabling the gateway with a small mixed catalog of servers.
#
# Drop this (adapted) into your home-manager configuration once
# `homeManagerModules.default` from this flake is imported. Two servers here:
# one launched via `npx` (needs Node on the agent's PATH — see `extraPath`),
# one via an absolute store path from natsukium/mcp-servers-nix.
{ pkgs, ... }:
{
  services.mcpGateway = {
    enable = true;

    # npx/uvx-launched servers resolve their runtime from here, since launchd
    # agents start with a minimal PATH.
    extraPath = [ pkgs.nodejs ];

    servers = {
      # A plain npx-launched server, no packaging needed.
      memory = {
        command = "npx";
        args = [
          "-y"
          "@modelcontextprotocol/server-memory"
        ];
      };

      # A packaged server pinned to a store path — bring your own package,
      # e.g. from natsukium/mcp-servers-nix's `lib.mkConfig`, or any
      # `writeShellApplication`/derivation that speaks MCP over stdio.
      fetch = {
        command = "${pkgs.mcp-server-fetch}/bin/mcp-server-fetch";
      };

      # A server needing a secret at launch: wrap the real command in a
      # script that fetches the value at RUN time rather than passing it via
      # `env` (which lands in the Nix store in plaintext). Here via the
      # macOS Keychain — swap in whatever secret store you use.
      example-with-secret = {
        command = "${pkgs.writeShellScript "example-mcp-server" ''
          set -eu
          export EXAMPLE_API_KEY="$(/usr/bin/security find-generic-password -a "$(id -un)" -s EXAMPLE_API_KEY -w 2>/dev/null || true)"
          exec ${pkgs.nodejs}/bin/npx -y example-mcp-server
        ''}";
      };
    };
  };

  # Wire the resulting endpoints into your MCP client of choice, e.g.
  # programs.claude-code.mcpServers (home-manager's claude-code module):
  #
  #   programs.claude-code.mcpServers = lib.mapAttrs (_: url: {
  #     type = "http";
  #     inherit url;
  #   }) config.services.mcpGateway.endpoints;
}
