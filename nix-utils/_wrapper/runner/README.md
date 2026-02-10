# nix-sandbox-runner

Rust runner used by the new sandbox wrapper migration.

## Check for newer dependencies + update lockfile

Run this from `_wrapper/runner`:

```bash
nix-shell -p cargo cargo-outdated --run 'cargo outdated && cargo update && cargo generate-lockfile'
```

What it does:

- `cargo outdated`: shows newer crate versions (compatible and latest).
- `cargo update`: updates `Cargo.lock` within your `Cargo.toml` constraints.
- `cargo generate-lockfile`: rewrites `Cargo.lock` deterministically.

## Verify after update

```bash
nix-shell -p cargo --run 'cargo check'
```
