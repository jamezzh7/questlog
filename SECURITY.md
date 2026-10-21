# Security policy

Security fixes target the latest source version. Questlog is an early-stage project; older versions do not have a separate security-maintenance branch.

## Reporting a vulnerability

Use this repository's **Security → Report a vulnerability** option when it is available. Include affected versions, a minimal fictional fixture, reproduction steps, and expected impact. Keep personal project data and credentials out of the report.

If private reporting is unavailable, open an issue asking the maintainer for a private reporting channel. Include only a general description; withhold exploit steps and sensitive details until a private channel is established. No response-time guarantee is offered.

## Relevant boundaries

- Project documents and tool registries are read-only inputs.
- Markdown reads must stay within the connected project, including when symlinks or relative links are involved.
- The local detail service binds to loopback and validates host, origin, and JSON writes. It is not intended to be exposed as a network service.
- Document text must remain inert when displayed in the web view.

The localhost service is not an authentication boundary against other software running as the same user. See [privacy and local data](docs/privacy.md) for what the app reads and stores.
