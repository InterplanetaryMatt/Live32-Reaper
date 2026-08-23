# Live32

**A virtual 32-channel live console for REAPER.**

Live32 turns REAPER into a software-defined live mixing console. REAPER remains the audio, routing and project engine in the background while Live32 provides a purpose-built live-console surface, custom JSFX processing, buses, matrices, DCAs, FX, scenes, routing, monitor/PFL/AFL behaviour and Sends on Faders.

> **Status: Public Beta — v1.2.3**  
> Live32 is ready for community testing, but it is not yet a finished/stable release. Please test on copies of projects you care about.

<img width="1436" height="962" alt="Screenshot 2026-08-19 184103" src="https://github.com/user-attachments/assets/7850ab19-093e-4f3e-955d-dfd1e3d5af6c" />

## Why Live32 exists

Live32 started as an experiment: could REAPER be made to behave like a modern digital live desk rather than a DAW? The answer turned out to be yes.

The project is intentionally **live-console-first**. It limits and presents controls in a way that encourages live mixing habits: select a source, adjust the channel processing, choose buses, use Sends on Faders, build monitor mixes, route matrices, work with DCAs and listen on a dedicated monitor/solo path.

The workflow is inspired by familiar digital live-console conventions, particularly the M32/X32 family, but Live32 is an independent project with its own DSP and implementation.

## Current feature set

- 32 input channels
- 8 FX return channels in linked stereo pairs
- 16 mix buses
- 8 matrix outputs
- 8 DCAs
- 6 mute groups
- Main LR master
- Dedicated Monitor/Solo bus
- Optional DAW Solo mode for stereo-only interfaces
- Channel PFL/AFL and bus/DCA AFL options
- Sends on Faders
- Odd/even stereo linking for channels and buses
- 24 dB/oct dedicated channel low-cut
- 4-band channel/FX-return EQ
- 6-band bus/Main EQ
- Gate and compressor with real activity indicators
- External key source and key filter
- Bus modes: Pre EQ, Post EQ, Pre Fader, Post Fader and Sub Group
- Main and bus sends to matrices
- Scenes and recall safe
- RTA overlay on EQ
- Scribble-strip naming and colours
- Hardware output routing page
- Transport controls
- Internal FX sends: Plate, Hall, one-shot Ping-Pong Delay and Chorus
- Insert processors: Precision Limiter, 31-band GEQ, FET 76-style compressor and Opto 2A-style leveler
- Launcher for new consoles, existing projects and multitrack import

## Installation

1. Download the latest release ZIP and extract the `Live32` folder somewhere permanent.
2. In REAPER open **Actions → Show action list**.
3. Choose **New action → Load ReaScript** and load `Live32_Launcher.lua`.
4. Run **Live32 Launcher**.
5. Choose one of:
   - **New Console** — build a fresh Live32 project.
   - **Attach Project** — use existing REAPER tracks directly as Live32 inputs.
   - **Import Multitrack** — copy selected media into a clean Live32 console while retaining the originals.
   - **Training Template** — build a labelled starting session.
6. The launcher installs the required custom JSFX automatically into REAPER's Effects folder.

For detailed instructions see [docs/INSTALL.md](docs/INSTALL.md).

## Monitor / Solo setup

Live32 now offers two solo systems, selected on the **MONITOR** page.

**Console Solo (default)** uses the dedicated Monitor/Solo path. Soloing a source does **not** interrupt Main LR. Route **Main LR** to FOH and **Monitor L/R** to a different hardware pair, then choose channel PFL/AFL, bus AFL and DCA AFL behaviour.

**DAW Solo** is intended for laptops and stereo-only interfaces. Enable **DAW Solo - use Main L/R** and Live32's Solo buttons use REAPER native solo-in-place through the normal Main L/R output. No separate monitor output is required. In this mode Main/FOH is intentionally affected and the PFL/AFL choices are bypassed.

Console Solo remains the safe default for live use.
<img width="576" height="361" alt="daw solo mode" src="https://github.com/user-attachments/assets/ef7125a8-1af6-4278-8744-b0e53977cb18" />


## Public beta testing

If you hit a bug, please include:

- OS
- REAPER version
- audio device/interface
- sample rate and buffer size
- Live32 version
- whether the project was New / Attached / Imported / Repaired
- exact steps that reproduce the issue
- exact ReaScript or JSFX error text, if any

A tester checklist is available at [docs/TESTER_CHECKLIST.md](docs/TESTER_CHECKLIST.md).

## Known limitations

See [KNOWN_ISSUES.md](KNOWN_ISSUES.md).

## Project structure

Live32 is built from two layers:

- **Lua / ReaScript** — console UI, routing, project construction, grouping, scenes, hardware patching and control logic.
- **JSFX** — real-time audio processing, metering, RTA and custom insert/FX processors.

REAPER remains the underlying audio engine.

## M32 / Midas compatibility

Live32 is **not** M32-EDIT and does not currently connect to or control a physical M32. A future network-control bridge is being explored, but it is not part of this beta.

Live32 is an independent project and is not affiliated with, endorsed by, or sponsored by Midas or Music Tribe. Midas, M32, X32 and related product names are trademarks of their respective owners and are referenced only to describe workflow inspiration and interoperability goals.

## AI-assisted development

Live32 was developed iteratively with AI assistance for Lua/ReaScript and JSFX implementation, debugging and code generation. The console design, workflow decisions, feature requirements and practical testing were developed interactively around real live-production workflows. Community review of the code is very welcome.

## Licence

MIT. See [LICENSE](LICENSE).

## Contributing

Bug reports, feature suggestions and code contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md).
