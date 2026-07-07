# Vendored Plannotator installer

`install.sh` is a mirrored copy of the official Plannotator installer, committed
here so `init.sh` runs a reviewed, pinned script instead of piping a live remote
script into `bash`.

## Provenance

- Source: https://plannotator.ai/install.sh
- Upstream repo: https://github.com/backnotprop/plannotator
- Vendored version target: `0.22.0` (see `PLANNOTATOR_VERSION` in `../../init.sh`)
- Vendored on: 2026-07-07
- sha256: `69a6338858fd1117599f4fe199d6cbd86329b0c4fd37ebe72ce1d62f39b58d75`

The installer still downloads the native CLI binary, the skills tree (sparse git
checkout at the pinned tag), and the `sem` sidecar from GitHub at runtime. Those
downloads are SHA256-verified by the script, and `init.sh` adds
`--verify-attestation` when `gh` is available for a SLSA build-provenance check.
Vendoring removes only the remote-script-into-bash step, not the artifact
downloads (the ~117MB binary is a per-platform release asset, impractical to
commit).

## Re-vendoring on a version bump

1. Fetch and review the new installer:

   ```bash
   curl -fsSL https://plannotator.ai/install.sh -o vendor/plannotator/install.sh
   chmod +x vendor/plannotator/install.sh
   git diff vendor/plannotator/install.sh   # review every change before trusting it
   shasum -a 256 vendor/plannotator/install.sh
   ```

2. Update this file: `Vendored version target`, `Vendored on`, and `sha256`.
3. Bump `PLANNOTATOR_VERSION` in `../../init.sh` to the new release tag (without
   the leading `v`; the installer normalizes it).
4. Run `./init.sh` with `PLANNOTATOR_UPDATE=1` to install the new release, then
   `make all`.
