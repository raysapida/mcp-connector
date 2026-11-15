## [Unreleased]

- Make sessions request-scoped: `Request#session` / `#session_id`, set by `initialize` and looked up from
  `run(json, session_id:)`
- Add an optional `session_store:` (with `InMemorySessionStore`) so multiple clients can share one connector without
  clobbering each other's session. Without a store, `current_session` is tracked as before
- Serve MCP's Streamable HTTP transport: an McpConnector is now a Rack app (`#call`), with `allowed_origins:`,
  `Mcp-Session-Id` sessions when a `session_store:` is given, and the Rack env available to authenticators
- Add `#prepare_request` for running requests outside of `#run`

## [1.0.1] - 2026-04-17

- Handle new clientInfo fields

## [1.0.0] - 2025-08-13

- Bump deps and version to unblock other upgrades

## [0.0.5] - 2025-05-03

- Handle changes to CommandConnector interface

## [0.0.4] - 2025-04-14

- Do not log requests/responses/errors by default

## [0.0.3] - 2025-04-14

- Grab version from gemspec instead of version.rb

## [0.0.2] - 2025-04-12

- Add more examples
- Update README.md with new examples
- Add description to gem

## [0.0.1] - 2025-04-11

- Initial release

## [0.0.0] - 2025-04-07

- Project birth
