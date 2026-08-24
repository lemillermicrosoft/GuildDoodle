# Changelog

## v0.2.0 - 2026-08-22

MVP: a working collaborative pixel canvas.

- 32x32 clickable canvas with movable, closable frame (ElvUI-safe, no protected calls).
- 16-color palette (index 0 = erase / right-click to erase).
- Per-player placement cooldown (default 30s, officer-configurable via `/doodle cooldown <s>`).
- Guild sync over the `DOODLE` addon channel:
  - `PIXEL:<x>:<y>:<c>:<ts>:<player>` on placement.
  - `HELLO` / `OFFER` election so only ONE guildie responds to a late-join sync.
  - `SNAP:<seq>/<total>:<hex>` chunked snapshot (hex-encoded 32x32 grid, 200 hex chars per chunk, well under the 255-char addon-message cap).
  - `CLEAR:<player>:<ts>` broadcast for officer canvas clears.
- SavedVariables persistence for grid, per-player cooldown timestamps, UI position, and selected color. Survives `/reload` and `/logout`.
- Idempotency: per-cell `appliedTs` ledger rejects duplicates and out-of-order pixel messages.
- Slash surface: `/doodle`, `/gd`, `/doodle color <0-15>`, `/doodle config`, `/doodle cooldown <s>` (officer), `/doodle clear` (officer), `/doodle help`.

## v0.1.0 - 2026-08-22

- Initial scaffold. Loads in-game, prints hello on `/doodle`.
