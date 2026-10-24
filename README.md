# Agentic Classic Mac Bridge

An agentic development environment for the classic Macintosh. Claude cross-compiles apps with
[Retro68](https://github.com/autc04/Retro68), deploys them to a Mac, runs them and reads back their
output, screenshots and crash reports, through one set of MCP tools that work against:

1. the [Snow](https://github.com/twvd/snow) emulator running a Mac SE with System 7.0.1, and
2. a real Macintosh SE, reached over its modem port through an ESP32 serial-to-Wi-Fi bridge.

System 6 support comes later. See [docs/plan.md](docs/plan.md) for the design and milestones.

## Status

Milestone M0/M1: repository scaffold, toolchain setup and a build loop with CI.

## Quick start

```sh
scripts/setup-toolchain.sh      # Retro68 + Snow from pinned sources (Retro68 takes ~1 hour)
scripts/build.sh                # builds apps/ into build/apps/
```

`build/apps/hello/Hello.bin` is a MacBinary application ready to copy to a Mac or an emulator disk.

## Layout

| Path | What |
|---|---|
| `apps/` | Mac applications (C, Retro68 CMake) |
| `scripts/` | toolchain setup, build, cloud session hook |
| `docs/` | plan and design notes |
| `.github/workflows/` | CI build of every app |

Planned additions per milestone: `emu/` (headless Snow runner and disk images), `protocol/` (wire protocol
spec), `nub/` (the Mac-side agent), `harness/` (test-app library), `host/` (Python client and MCP server),
`crashinit/`, `firmware/esp32/`.

ROMs and Apple system software are never committed.
