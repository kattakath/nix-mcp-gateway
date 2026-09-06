{
  description = "A home-manager MCP gateway: one localhost mcp-proxy launchd agent hosting your own set of MCP servers over HTTP, so every AI CLI/client points at a single shared endpoint instead of spawning its own stdio copy of each server.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  nixConfig = {
    extra-substituters = [ "https://kattakath.cachix.org" ];
    extra-trusted-public-keys = [
      "kattakath.cachix.org-1:y/w6wnb4ZArdlbfWJ82c81uCXeYgG/sGDUYCszavmEw="
    ];
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      treefmt-nix,
    }:
    let
      inherit (nixpkgs) lib;
      darwinSystems = [
        "aarch64-darwin"
      ];
      forAll = systems: f: lib.genAttrs systems (system: f system nixpkgs.legacyPackages.${system});

      # treefmt owns `nix fmt` and supplies its own `checks.treefmt` gate, so CI
      # needs no hand-rolled formatting step — `nix flake check` runs the
      # formatter from THIS flake's lock rather than the runner's registry.
      # Bare nixfmt as the formatter is a trap: `nix fmt` hands it every file in
      # the tree, including README.md and LICENSE, which it cannot parse.
      # This is a plain flake, so it takes treefmt-nix's non-flake-parts entry
      # point: upstream option treefmt-nix.lib.evalModule exists -> using it.
      treefmtEval = forAll darwinSystems (
        _: pkgs:
        treefmt-nix.lib.evalModule pkgs {
          projectRootFile = "flake.nix";
          programs.nixfmt.enable = true;
          programs.deadnix.enable = true;
          programs.statix.enable = true;
        }
      );
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

          treefmt = treefmtEval.${system}.config.build.check self;
        }
      );

      formatter = forAll darwinSystems (system: _: treefmtEval.${system}.config.build.wrapper);
    };
}
