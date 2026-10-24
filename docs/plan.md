# Agentic Mac dev environment: implementation plan

*Plan, 2026-10-24 (updated during M0: headless Snow runner). Builds on [research/mac-se-interconnect.md](../research/mac-se-interconnect.md); design reasons are there and not repeated here. Items marked "(verify)" get checked in the milestone that first depends on them.*

## The plan in one paragraph

Build one toolchain, one Mac-side agent ("the nub"), one wire protocol and one MCP server, and point them at two targets: the **Snow emulator running a Mac SE**, then the **real SE over the ESP32**. Snow emulates the SE itself and bridges its serial port to a host pty or TCP socket, so the exact nub binary that runs in the emulator also runs on the real machine, and the same disk image can boot both (Snow's SCSI disk and the SCSI2SD card). The emulator path runs entirely inside a Claude cloud session, so most of the work needs nothing from Jeff's desk. The hardware path runs on Jeff's desktop through Remote Control, only during dev sessions.

```
Claude
  │  MCP tools (same set for both targets)
  ▼
host/  (Python: protocol client + MCP server + CLI)
  │                              │
  │ pty / TCP                    │ TCP (ZiModem raw now, custom firmware later)
  ▼                              ▼
Snow (SE, Xvfb, cloud)         ESP32 ──serial── real Mac SE (SCSI2SD)
  └── nub on System 7.0.1        └── same nub, same disk image
```

## Key decisions

| Decision | Choice | Why |
|---|---|---|
| Toolchain | **Retro68** (GCC 68k, CMake, Toolbox headers), built for 68000 | Produces System 6/7 apps and MacBinary; has `LaunchAPPL` with serial/TCP/shared backends we can bootstrap with |
| Primary emulator | **Snow**, Mac SE model, System 7.0.1 | Same machine as the target (68000, SE ROM, SCC serial); serial bridged to TCP/pty since v1.2; SCSI HD images; debugger; MIT license |
| Fallback emulators | Mini vMac (SE build) for `LaunchAPPL --emulator minivmac` quick runs; Basilisk II only if we need faster 7.x testing | Mini vMac has no serial, so it can't run the nub; it's a sanity check, not the main path |
| How Claude "sees" the emulator | A small **headless runner** built on Snow's `snow_core` crate: it boots the SE, bridges the modem port, and exposes a control socket for framebuffer screenshots, input, reset and memory reads. Screenshots via the nub too (same as hardware). Fallback: the Snow GUI under Xvfb with `xdotool` | Snow's GUI has no headless mode, but its own `testrunner` drives `snow_core` with no GUI (`Emulator::new`, `tick`, frame channel, `EmulatorCommand`), so a headless runner is a small Rust program |
| Host language | **Python** (pyserial, official MCP SDK) | Easy to run on the cloud container and Jeff's desktop; one package gives MCP server, CLI and test library |
| Nub transport | One framed binary protocol, transport-agnostic (pty, TCP, serial) | Same nub everywhere |
| Disk images | One "golden" HFS image built by script (hfsutils/`hcopy`), booting both Snow and SCSI2SD | Parity between targets; reproducible (verify Snow and SCSI2SD both accept the same raw partitioned image) |
| Where Claude runs | Emulator work: cloud sessions. Hardware work: Claude Code on jeff-desktop via Remote Control | Cloud can't reach the LAN; nub must never be exposed to the internet |

## How Claude drives it: the MCP tool set

Same tools against either target (`target: "snow" | "se"` in config, not per call):

| Tool | What it does | Available from |
|---|---|---|
| `build(app)` | CMake/Retro68 build, returns errors | M1 |
| `boot` / `shutdown` | Start or stop Snow (emulator) | M2 |
| `ping` | Is the nub alive, which system, how much memory | M3 |
| `deploy_and_run(app, timeout)` | Send app, launch it, stream its stdout until it quits or times out | M3 |
| `read_log` | Recent stdout / event log from the nub | M3 |
| `screenshot` | 512×342 1-bit screen from the nub, returned as PNG | M4 |
| `put_file` / `get_file` / `list_dir` / `delete` | File ops with both forks and type/creator | M4 |
| `quit_app` | Quit the app under test (Apple Event on 7, harness poll on 6) | M4 |
| `peek` / `gestalt` / `heap_info` | Debug and environment checks | M4 |
| `crash_report` | Last SysError ID, PC, registers from the crash INIT | M7 |
| `reset(kind)` | Emulator: restart Snow. SE: ESP32 pulses reset or NMI | M2 (emu), M6 (SE) |
| `screen_grab` | Emulator: X11 capture. SE: none (or webcam later) | M2 |
| `send_keys` / `click` | Emulator: xdotool. SE: ADB emulation | M2 (emu), M9 (SE) |

A repo skill (`.claude/skills/mac-dev`) tells Claude the edit-build-deploy loop, the memory limits, and how to recover from a crash (reset, wait for `ping`, read `crash_report`).

## Phases and milestones

Each milestone ends with something Claude can demonstrate on its own. Rough sizes assume one thread per milestone.

### Stage A: emulator (cloud sessions)

**M0. Repo and environment** (small)
- Jeff creates the GitHub repo (I can't create repos); I attach it and scaffold the layout below.
- Cloud environment setup script installs Retro68 (prebuilt from a cached tarball or the Retro68 Docker image, since building it from source takes about an hour), Snow, Xvfb, xdotool, hfsutils, Python deps.
- Done when: a fresh cloud session has `m68k-apple-macos-gcc` and `snow` on the path.

**M1. Build loop** (small)
- `apps/hello` (console app) and a CMake preset for 68000 / System 7.
- GitHub Actions builds every app on each push and uploads MacBinary artifacts.
- Done when: `build hello` produces `hello.bin` locally and in CI.

**M2. Emulator boots, Claude can see it** (medium)
- Needs from Jeff: an **SE ROM image** (ideally dumped from his own SE; a dump tool can run once the nub exists, but the emulator needs one first) and **System 7.0.1 install disks** (Apple distributed 7.0.1 freely; verify a clean source). ROMs and system software are kept out of git: stored in an environment secret or private storage and fetched by the setup script.
- `emu/make-disk.sh` builds the golden image: System 7.0.1, 4 MB SE, `LaunchAPPLServer` in Startup Items, serial set to the modem port.
- `emu/snow-headless/` (Rust, on `snow_core` v1.5.0): loads ROM and `hddN.img` disks, bridges the modem port to a pty or TCP port, and serves a JSON control socket (`screenshot`, `key`, `mouse`, `reset`, `peek`, `status`). The Snow GUI has `--serial-bridge-a pty|tcp:PORT` and can stay as a manual fallback under Xvfb.
- First MCP tools: `boot`, `shutdown`, `reset`, `screen_grab`, `send_keys`.
- Done when: Claude boots the SE in Snow and returns a screenshot of the 7.0.1 desktop.

**M3. First loop through serial, nub v0** (medium)
- Use `LaunchAPPL --emulator serial` against the pty to run `hello` on the emulated SE: proves serial, Startup Items and the build output end to end.
- Then the first own nub (start from `LaunchAPPLServer`'s source): protocol v1 framing (COBS, header with type/seq/len, CRC-16, stop-and-wait ACK/NAK, ≤512-byte packets, version handshake), `ping`, `put_file`, `launch`, stdout events.
- `protocol/spec.md` written first, with test vectors shared by the C and Python sides.
- MCP tools `ping`, `deploy_and_run`, `read_log`.
- Done when: Claude edits `hello.c`, runs `deploy_and_run`, and reads its output, with no GUI clicks.

**M4. Nub v1 and test harness** (large)
- File ops (both forks, type/creator), `list_dir`, `screenshot` (PackBits), `peek`/`gestalt`/`heap_info`, `quit_app` via Apple Event.
- `harness/` library linked into test apps: redirects stdout to the nub, answers quit, reports exit status.
- Nub core is plain Toolbox; launch/quit sits behind a small interface (`sys7/` now, `sys6/` later).
- Host test suite (pytest) runs against Snow in CI if Snow runs headless there (stretch goal).
- Done when: Claude builds a small windowed app, launches it, screenshots it via the nub, quits it, and pulls a log file back.

### Stage B: real Mac SE (Jeff's desktop, Remote Control)

**M5. Same nub on the real SE over ZiModem** (medium)
- Flash the golden image (with the nub in Startup Items) to the SCSI2SD card. Confirm the SE boots it.
- ZiModem set binary-clean: hardware flow control on (`AT&K3`), escape `+++` disabled, Telnet off, raw TCP listen (verify exact AT commands for transparent mode). Handshake lines are already wired and confirmed (2026-10-24).
- Host gets a TCP transport; MCP config `target: se, host: <esp32 ip>`.
- Find the reliable baud rate on the real unit (aim 57.6k, fall back 19.2k).
- Done when: from jeff-desktop, Claude runs `deploy_and_run hello` on the physical SE.
- Needs from Jeff: one SD card swap, ESP32 IP, Remote Control session.

**M6. Custom ESP32 firmware** (medium)
- `firmware/esp32/` (PlatformIO, Arduino core). Keeps ZiModem's pins (UART2 16/17, CTS 13, RTS 15).
- Binary-clean serial↔TCP bridge with RTS/CTS and buffering; a second TCP port for status (link stats, reset events); OTA updates so reflashing needs no USB.
- **Reset and NMI lines**: two opto-isolated GPIOs across the SE's programmer's switch contacts. Needs a small, reversible hardware addition from Jeff (opto + resistors; wiring plan delivered in this milestone).
- MCP `reset(kind="reset"|"nmi")` on the SE.
- Done when: Claude crashes the SE on purpose, resets it, and sees `ping` come back without Jeff touching the machine.

**M7. Crash diagnostics** (medium)
- `crashinit/`: an INIT that patches the system error handler to send error ID, PC and registers over serial before the bomb box, then lets the reset path recover. Works in Snow first (Snow's debugger helps here), then on the SE.
- MCP `crash_report`. Optional: MacsBug on the image so NMI drops into it and its output is captured.
- Done when: a deliberately bad app produces a readable crash report in Claude's tool output, on both targets.

### Stage C: breadth

**M8. System 6 target** (medium to large)
- Second golden image with System 6.0.8 and MultiFinder (nub as a startup app). If MultiFinder proves too fragile, fall back to an INIT/driver nub.
- `sys6/` launch/quit layer: `_Launch`, harness-poll quit, no Apple Events. Build presets per system.
- Done when: the M4 demo passes on System 6 in Snow, then on the SE.

**M9. Hands and eyes** (large, optional)
- ADB keyboard/mouse emulation on the ESP32 (5 V open-collector, level shifter needed), so `send_keys`/`click` work on the real SE.
- Optional USB webcam on jeff-desktop for after-crash screenshots.
- Optional transport upgrade: BlueSCSI v2 + Pico W (Wi-Fi SCSI) instead of serial.

## Recommended repo layout

```
macdev/                     (name is Jeff's call)
├── CLAUDE.md               loop, limits, how to recover a crashed target
├── .claude/skills/mac-dev/ skill for the edit-build-deploy loop
├── .mcp.json               registers host/ as the MCP server
├── protocol/
│   ├── spec.md             wire protocol v1
│   └── vectors/            test vectors used by C and Python tests
├── nub/                    Mac agent app (C, Retro68)
│   ├── core/               serial, framing, file ops, screenshot
│   ├── sys7/               launch/quit via Process Manager + Apple Events
│   └── sys6/               launch/quit for MultiFinder (M8)
├── harness/                library linked into test apps
├── crashinit/              SysError-patching INIT (M7)
├── apps/                   sample and test apps (hello, window demo, crash test)
├── host/                   Python package
│   ├── macdev/transport/   pty, tcp, serial
│   ├── macdev/protocol.py
│   ├── macdev/mcp_server.py
│   └── tests/
├── emu/                    run.sh, make-disk.sh, Snow config
├── firmware/esp32/         PlatformIO project (M6)
├── images/                 gitignored: ROMs, system disks, golden images
└── .github/workflows/      build apps; host unit tests
```

## What I need from Jeff, and when

| When | What |
|---|---|
| Before M0 | Create an empty GitHub repo and tell me its name |
| Before M2 | An SE ROM image and System 7.0.1 disks (or OK for me to locate Apple's free 7.0.1 release); where to keep them privately |
| M5 | Swap the SCSI2SD card (back up the current one first), ESP32 IP, start a Remote Control session on jeff-desktop |
| M6 | Fit the reset/NMI opto board to the programmer's switch |
| M8 | System 6.0.8 disks |

## Risks and fallbacks

- **Headless runner harder than expected** (e.g. serial bridge lives in the GUI crate): run the Snow GUI under Xvfb with `--serial-bridge-a` and grab the screen with X11 tools; worst case use Mini vMac for M1–M2 and Snow only for serial tests.
- **Retro68 setup time in cloud sessions**: cache a prebuilt toolchain tarball (release asset in the repo) so setup takes minutes.
- **`LaunchAPPLServer` misbehaves on a 68000 under 7.0.1**: skip straight to our own nub in M3; the bootstrap is a convenience, not a dependency.
- **Serial reliability on the real SE**: drop baud, shrink packets, rely on CRC and retry; RTS/CTS is already wired.
- **Shared disk image not accepted by one target**: keep separate images built by the same script.
- **ROM/system licensing**: never commit ROMs or Apple system software to the repo.
