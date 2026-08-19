# Contributing to Live32

Thanks for helping test or improve Live32.

## Bug reports

Please include:

1. Live32 version.
2. REAPER version.
3. OS.
4. Audio interface/device.
5. Sample rate and buffer size if the issue is audio/routing related.
6. How the project was created: New, Attach, Import or Repair.
7. Exact steps to reproduce.
8. Exact ReaScript/JSFX error text.
9. A screenshot where useful.

Please test on a copy of the project before sharing project files publicly.

## Pull requests

Keep changes focused and explain:

- what problem the change solves;
- whether it affects audio/DSP, project structure or UI only;
- how it was tested;
- whether it changes existing project compatibility.

For DSP changes, include the intended filter/dynamics behaviour and any assumptions made.

## Design principle

Live32 is a **live-console workflow first**. New features should generally make the software behave more like a coherent live desk rather than adding DAW-style complexity for its own sake.

## Code areas

- `Live32_Console.lua` — UI and console-control logic.
- `Live32_Launcher.lua` — project entry point.
- `Live32_Setup.lua` — console/project construction and repair.
- `*.jsfx` — audio DSP, metering and analysis.
