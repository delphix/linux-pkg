# Conventions for Claude Code in this repo

## Testing a change

See [docs/testing.md](docs/testing.md) — how to test a change to `linux-pkg` itself, how CI for a
package works, and how to use `linux-pkg` to build/validate a change made in one of the many
packages it orchestrates.

## Keeping this file and docs/testing.md current

A change to a tool, option, mode, job, or package list — or a newly found (or fixed) gotcha —
should update `docs/testing.md`. If this repo ever gains a second AI-agent instruction file (e.g.
`.github/copilot-instructions.md`, which does not exist today), carry this same testing-doc
pointer into it too; nothing keeps two such files in sync automatically.
