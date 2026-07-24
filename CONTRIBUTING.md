# Contributing

A small, focused, macOS-only home-manager module — contributions that keep it
that way are the most welcome. This project deliberately does NOT grow into a
per-server Nix packaging catalog (see [natsukium/mcp-servers-nix](https://github.com/natsukium/mcp-servers-nix)
for that); it stays scoped to the runtime gateway.

## Dev loop

```sh
nix flake check -L                       # module eval check
nix run nixpkgs#nixfmt-rfc-style -- .    # format all .nix (CI enforces this)
nix flake show
```

## Guidelines

- Keep `services.mcpGateway.servers` a thin `{ command; args; env; }` shape —
  do not bake in any specific server, provider, or client.
- No secret values in code or examples, ever.
- Every new option needs a `description`.
- Update `README.md` for user-facing changes; CI (format + flake show + eval
  check) must pass.
