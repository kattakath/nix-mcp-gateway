# Security Policy

## The model (important)

`mcp-gateway` runs a **loopback-only** `mcp-proxy` launchd agent hosting the
MCP servers you configure. It does no authentication of its own — anything
that can reach `host:port` (default `127.0.0.1:8096`) can call every hosted
server. Keep `host` on loopback unless you have your own reason (and your own
auth/firewalling) to expose it further.

- `servers.<name>.env` values are written to the generated JSON config, which
  lives in the **world-readable** Nix store — plaintext, non-secret
  configuration only. Do not put API keys or connection strings there; wrap
  the server's `command` in a script that fetches the secret at *run* time
  instead (see the README's "Secrets" section).
- The generated launchd plist and log file are only as private as your local
  user account / filesystem permissions.

## Reporting a vulnerability

Please open a **private** security advisory via GitHub
("Security" → "Report a vulnerability"), or contact the maintainer directly.
Do not file public issues for undisclosed vulnerabilities.
