# GuildDoodle

A shared pixel canvas for your WoW guild. r/place, but small and cozy.

Everyone in the guild sees the same canvas. Anyone can drop a pixel every 30 seconds. State syncs over the guild addon channel. Persists across `/reload` and `/logout`.

Built for **WoW TBC Classic 2.5.6** (Interface 20506).

## Install

1. Copy the `GuildDoodle` folder into `World of Warcraft\_classic_\Interface\AddOns\`.
2. Restart the client or `/reload`.
3. `/doodle` (or `/gd`) to open the canvas.

## Usage

- **Left-click** a cell to paint with the selected color.
- **Right-click** a cell to erase (equivalent to color `0`).
- Click a palette swatch to change color.
- Drag the frame's background to move it — position is saved.

Every placement respects your personal cooldown (default 30s, shown at the bottom of the frame). Blocked cleanly during combat — no protected calls.

## Slash commands

| Command | What it does |
| --- | --- |
| `/doodle` or `/gd` | Toggle the canvas window |
| `/doodle color <0-15>` | Select paint color; `0` = erase |
| `/doodle config` | Show current grid size, cooldown, painted-cell count, officer status |
| `/doodle cooldown <s>` | *(officer)* Set per-player placement cooldown, 0–3600s |
| `/doodle clear` | *(officer)* Clear the canvas and broadcast to guild |
| `/doodle help` | List commands |

"Officer" is a soft UI-side check: `IsGuildLeader()` or `CanEditOfficerNote()`.

## How sync works

Wire protocol on the `DOODLE` addon prefix, channel `GUILD`:

- `PIXEL:<x>:<y>:<c>:<ts>:<player>` — a single placement.
- `HELLO:<player>` — I just logged in / reloaded, give me the current canvas.
- `OFFER:<player>` — I'll answer that HELLO (election message).
- `SNAP:<seq>/<total>:<hex>` — chunked snapshot payload (200 hex chars per chunk).
- `CLEAR:<player>:<ts>` — an officer cleared the canvas.

**HELLO election:** every online client rolls a random 0.5–2.5s delay when it sees a HELLO. First one to fire sends `OFFER`; the rest see it and cancel their timer. Prevents 30 guildies all snapshot-blasting at once.

**Idempotency:** per-cell `appliedTs` ledger. Duplicate or older pixel messages are dropped silently.

**Snapshot format:** the 32×32 grid is serialized as `y*32 + x` nibbles (0..15), so a full canvas is 1024 nibbles = 512 hex chars → ~3 chunks. Comfortably under the 255-char per-message cap.

## Safety notes

- Never calls any protected function; never injects into Blizzard event dispatchers.
- `InCombatLockdown()` gates painting attempts.
- Loads clean with ElvUI (no `SetPoint` on protected frames, no `BackdropTemplate` fallback issues — the `BackdropTemplate` check gracefully no-ops on older builds).

## Data

Everything lives in `GuildDoodleDB` under WTF `SavedVariables`:

- `pixels` — sparse `"x,y"` → `{ c, t, p }` map.
- `appliedTs` — dedup ledger.
- `lastPlace` — per-player last placement epoch.
- `ui` — window position, visibility, selected color.
- `cooldown`, `gridSize` — configurable knobs.

## Post-MVP roadmap

- 64×64 grid (perf work).
- Weekly reset scheduler.
- Named canvases (`/doodle canvas raid-night`).
- Undo-my-last-pixel.
- TGA screenshot export.

## Requests

DM deehoc: `!addon guilddoodle <what you want>`.
