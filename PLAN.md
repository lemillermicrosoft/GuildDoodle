# PLAN

## Vision

A shared 32x32 (or 64x64) pixel canvas that guildies can collaboratively paint, one pixel at a time, with a cooldown between placements. State syncs via addon channel so anyone online sees changes in near-real-time. A cozy, low-stakes ambient AFK activity.

## MVP scope

1. **Canvas frame**: a resizable UI with a grid of clickable pixel cells.
2. **Color palette**: 16-color palette (safe colors that look good on WoW UI). Click to select active color.
3. **Placement cooldown**: default 30s between pixel placements per player. Configurable by an officer role.
4. **Sync protocol**: on placement, broadcast `PIXEL:<x>:<y>:<colorIdx>:<player>` via `SendAddonMessage("DOODLE", ..., "GUILD")`. On receive, update local canvas + save.
5. **Late-join snapshot**: on `PLAYER_ENTERING_WORLD`, request `HELLO`; any online guildie responds with `SNAPSHOT:<base64 of grid>` (chunked if too big for 255-char limit).
6. **Persistence**: canvas state in SavedVariables; survives /reload and re-login.

## Technical tasks

- Grid rendering via nested `CreateFrame("Button", ...)`. Consider a bitmap texture approach for perf if 64x64 is too many frames.
- Base64 (or hex) encode/decode of pixel grid for snapshot messages.
- Message chunking: 255-char limit per addon message; snapshot may need 5-10 chunks with sequence numbers.
- Anti-spam: reject own messages we already applied locally (idempotent by (x,y,colorIdx) and monotonic timestamp).
- Rate limiter for outgoing snapshot responses (one guildie answers per HELLO, not all).

## QA

- Verify pixels persist across /reload.
- Two clients: place a pixel on A, see it on B within a second.
- Snapshot exchange completes for a fully-covered canvas within 10 seconds.
- No addon-channel spam if 20 people are placing simultaneously.
- No taint: no protected calls; no SetPoint on protected frames.

## Post-MVP

- Weekly canvas reset (officer command).
- Named canvases (`/doodle canvas raid-night`).
- Undo-my-last-pixel button.
- Export canvas as .tga screenshot.

## Deliverables

- Working addon that loads clean in TBC Classic 2.5.6.
- README + CHANGELOG.
- GitHub repo + CurseForge project (deehoc creates the CF side).
- Feature request pipeline via `!addon guilddoodle <request>`.
