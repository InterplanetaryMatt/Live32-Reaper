# Live32 v1.2.3-beta

## Hotfix

This release fixes the ReaScript error that could occur when enabling **DAW Solo - use Main L/R** while no source was currently soloed.

The Monitor-page meter now treats that state as silence until a channel, FX return, bus, matrix, or DCA member is soloed.

There are no DSP, routing, or project-structure changes from v1.2.2. Existing users can update only `Live32_Console.lua`.
