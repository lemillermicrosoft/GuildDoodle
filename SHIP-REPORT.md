# SHIP REPORT — GuildDoodle v0.2.0 MVP

## PR

- **Branch:** `feat/mvp-v0.2.0`
- **PR URL:** https://github.com/lemillermicrosoft/GuildDoodle/pull/2
- **Title:** `feat: GuildDoodle v0.2.0 MVP`
- **Target:** `main`

## What shipped

Everything in `PLAN.md`'s **MVP scope** section:

1. ✅ 32x32 canvas frame, movable, closable, ElvUI-safe. Position + visibility persisted.
2. ✅ 16-color palette (indices 1–15) plus index 0 (erase / right-click) with click-to-select and a highlight ring on the active swatch.
3. ✅ Per-player placement cooldown, default 30s, officer-configurable via `/doodle cooldown <s>`. Displayed live at the bottom of the frame.
4. ✅ `SendAddonMessage("DOODLE", "PIXEL:<x>:<y>:<colorIdx>:<ts>:<player>", "GUILD")` on placement. Prefix registered via `C_ChatInfo.RegisterAddonMessagePrefix` (falls back to legacy API).
5. ✅ Late-join snapshot: `HELLO` → randomized-delay election → `OFFER` (only ONE guildie sends) → chunked `SNAP:<seq>/<total>:<hex>` (200 hex chars per chunk, comfortably under the 255-char cap). Hex codec is a nibble-per-cell serialization; a full 32x32 canvas is 512 hex chars ≈ 3 chunks.
6. ✅ Persistence via `GuildDoodleDB` SavedVariables. Survives `/reload` and `/logout`.
7. ✅ Idempotency: per-cell `appliedTs` ledger rejects duplicate/out-of-order pixel messages.

Slash surface: `/doodle`, `/gd`, `/doodle color <0-15>`, `/doodle config`, `/doodle cooldown <s>` (officer), `/doodle clear` (officer, broadcasts CLEAR), `/doodle help`.

Officer soft-check: `IsGuildLeader() or CanEditOfficerNote()`, per spec.

Combat safety: `InCombatLockdown()` gates every paint attempt. No protected function calls anywhere. Own event frame — no injection into Blizzard dispatchers.

## What was deferred (post-MVP per PLAN.md)

- 64x64 grid (perf pass; 32x32 is the MVP baseline per the brief).
- Weekly canvas reset scheduler.
- Named canvases (`/doodle canvas <name>`).
- Undo-my-last-pixel button.
- TGA screenshot export.

## Files touched

| File | Change |
| --- | --- |
| `GuildDoodle.toc` | Version bumped `0.1.0` → `0.2.0`; loads `Core.lua`, `Comm.lua`, `UI.lua`, `Slash.lua`. |
| `GuildDoodle.lua` | **Removed** (superseded by split modules). |
| `Core.lua` | **New.** Namespace, SavedVariables, palette, constants, hex codec, idempotency, event dispatcher. |
| `Comm.lua` | **New.** Wire protocol: `PIXEL`, `HELLO`/`OFFER` election, chunked `SNAP`, `CLEAR`. |
| `UI.lua` | **New.** Canvas frame, palette, click-capture, cooldown ticker. |
| `Slash.lua` | **New.** `/doodle` and `/gd` command surface. |
| `CHANGELOG.md` | Prepended v0.2.0 entry. |
| `README.md` | Rewritten with real user + protocol docs. |
| `.gitignore` | Ignore local `.agent/node_modules/` sanity tooling. |
| `.agent/lua-parse.js` | Local Lua-parser sanity checker (Node + luaparse). |

## How verified

- **Lua syntax:** Parsed all four Lua files with the `luaparse` npm package in Lua 5.1 mode (WoW's dialect). All four came back clean:
  ```
  [ ok ] Core.lua
  [ ok ] Comm.lua
  [ ok ] UI.lua
  [ ok ] Slash.lua
  ```
- **Design review** of the tricky bits:
  - **HELLO election:** each client rolls `0.5 + rand()*2.0`; on receiving any `OFFER` before their own timer fires, they cancel. Guarantees the "only ONE responder" spec.
  - **Snapshot chunking:** longest possible chunk is `"SNAP:99/99:" + 200 hex` = 211 chars, well under 255.
  - **Idempotency:** `appliedTs[key]` is stamped by every write path (local click, remote PIXEL, snapshot decode, CLEAR). Older/equal ts is rejected.
  - **Combat:** `InCombatLockdown()` guard on the OnMouseDown handler is the sole gate needed — no protected calls elsewhere.
  - **ElvUI:** `BackdropTemplate` used defensively via `if frame.SetBackdrop then`; nothing hooks into ElvUI-touched frames.
- **In-client smoke test:** NOT performed by this subagent — parent will smoke-test in TBC Classic before tagging/release, per the "do not tag or ship to CurseForge" instruction.

## Notes for parent

- CurseForge release + tag is intentionally not done. Parent handles that side.
- If the parent wants Deehoc-visible logging on snapshot receive to be quieter, the `ns.Print` in `Comm.lua` under the `SNAP` complete branch is the knob.
