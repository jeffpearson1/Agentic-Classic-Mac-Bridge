# Agentic Classic Mac Bridge

Tooling that lets Claude build, deploy, run and debug software on a classic Macintosh:
first the Snow emulator (emulating a Mac SE), then a real Mac SE over serial via an ESP32.
Target: System 7.0.1 now, System 6 later. The phased plan is in `docs/plan.md`; check which
milestone is current before starting new work.

## Target machine

- Macintosh SE: Motorola 68000, 4 MB RAM, 512×342 1-bit screen, SCSI2SD disk.
- Compile for plain 68000 (`-m68000`, set in `apps/CMakeLists.txt`). No 68020+ instructions, no FPU, no Color QuickDraw.
- No memory protection: a bad pointer takes the whole Mac down. Prefer small, defensive code and check `OSErr` results.
- Check for features with `Gestalt` before using them; System 6 lacks Apple Events and the Process Manager.

## Toolchain

- Retro68 (GCC for 68k), installed at `/opt/retro68`. Snow emulator binaries at `/opt/snow/bin`.
- `scripts/setup-toolchain.sh` installs both from pinned sources. A from-source Retro68 build takes about an hour,
  so run it in the background. `--save-cache` writes tarballs to `/mnt/project-files/cache/` and the SessionStart
  hook (`scripts/session-start.sh`) restores them in later cloud sessions.
- `scripts/build.sh [target]` builds everything under `apps/`. Output is in `build/apps/<app>/`:
  `<Target>.bin` (MacBinary, what gets deployed), `.dsk` (800K-style disk image), `.APPL`.
- CI (`.github/workflows/build.yml`) builds all apps in the `ghcr.io/autc04/retro68` image.

## Adding an app

Create `apps/<name>/` with a `CMakeLists.txt` that calls `add_application(...)` (add `CONSOLE` for a
stdio app), then `add_subdirectory(<name>)` in `apps/CMakeLists.txt`. Console apps used in automated runs
must exit on their own; never wait for a keypress.

## Never commit

Mac ROM images, Apple system software, or disk images built from them (`.gitignore` covers the usual
extensions and `images/`). Keep them in `images/` locally or in private project storage.
