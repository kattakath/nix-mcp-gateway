{
  description = "A home-manager MCP gateway: one localhost mcp-proxy launchd agent hosting your own set of MCP servers over HTTP, so every AI CLI/client points at a single shared endpoint instead of spawning its own stdio copy of each server.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  nixConfig = {
    extra-substituters = [ "https://ismailkattakath.cachix.org" ];
    extra-trusted-public-keys = [
      "ismailkattakath.cachix.org-1:7BbEvLpASY7aNUZfpzRMWir1zjU3nqmllBTl8p7gr2I="
    ];
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
    }:
    let
      inherit (nixpkgs) lib;
      darwinSystems = [
        "aarch64-darwin"
      ];
      forAll = systems: f: lib.genAttrs systems (system: f system nixpkgs.legacyPackages.${system});
    in
    {
      # The reusable home-manager module (system-agnostic; no-op off macOS).
      homeManagerModules.mcpGateway = ./modules/mcp-gateway.nix;
      homeManagerModules.default = self.homeManagerModules.mcpGateway;

      # Eval check: the module wires up a launchd agent for a user-supplied
      # `servers` set and computes the matching gateway endpoint URLs.
      checks = forAll darwinSystems (
        system: pkgs:
        let
          hm = home-manager.lib.homeManagerConfiguration {
            inherit pkgs;
            modules = [
              self.homeManagerModules.default
              {
                home.username = "tester";
                home.homeDirectory = "/Users/tester";
                home.stateVersion = "24.05";
                services.mcpGateway = {
                  enable = true;
                  servers.demo = {
                    command = "${pkgs.coreutils}/bin/true";
                    args = [ "--stdio" ];
                  };
                };
              }
            ];
          };
          agent = hm.config.launchd.agents.mcp-gateway.config;
        in
        {
          module-evaluates = pkgs.runCommand "mcp-gateway-eval" { } ''
            test "${lib.elemAt agent.ProgramArguments 2}" = "127.0.0.1"
            test "${lib.elemAt agent.ProgramArguments 4}" = "8096"
            test "${hm.config.services.mcpGateway.endpoints.demo}" = "http://127.0.0.1:8096/servers/demo/mcp"
            grep -q '"demo"' "${lib.elemAt agent.ProgramArguments 6}"
            echo ok > "$out"
          '';
        }
      );

      formatter = forAll darwinSystems (_: pkgs: pkgs.nixfmt-rfc-style);
    };
}
