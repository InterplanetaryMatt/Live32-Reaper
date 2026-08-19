# Live32 Public Beta Tester Checklist

You do not need to test everything. Even one section is useful.

## Installation
- [ ] Launcher loads without a ReaScript error.
- [ ] New Console builds successfully.
- [ ] Console opens after setup.
- [ ] Bundled JSFX appear without compile/runtime errors.

## Existing projects
- [ ] Attach Project works with selected tracks.
- [ ] Import Multitrack preserves the original source project safely.
- [ ] Track names map sensibly to Live32 scribble strips.

## Channel processing
- [ ] 24 dB/oct Low Cut audibly works.
- [ ] Gate works and GATE activity lamp reflects actual gate closure.
- [ ] Compressor works and COMP activity lamp reflects actual gain reduction.
- [ ] 4-band channel EQ works.
- [ ] EQ RTA display behaves sensibly.

## Buses / outputs
- [ ] Bus 1–16 send levels work.
- [ ] Sends on Faders works.
- [ ] Pre EQ / Post EQ / Pre Fader / Post Fader modes work.
- [ ] Sub Group membership workflow works.
- [ ] Bus 6-band EQ works.
- [ ] Main LR 6-band EQ works.
- [ ] Bus/Main → Matrix sends work.

## Linking
- [ ] Odd/even channel link copies the left/odd state and remains ganged.
- [ ] Linked pair is hard L/R.
- [ ] Linked stereo sends maintain L/R behaviour.
- [ ] FX return pairs remain hard L/R.

## DCA / mute groups
- [ ] DCA membership works.
- [ ] DCA fader behaves as expected.
- [ ] DCA mute works.
- [ ] DCA solo feeds the monitor path without interrupting Main LR.
- [ ] Mute groups work.

## FX / inserts
- [ ] Plate works.
- [ ] Hall works.
- [ ] One-shot ping-pong delay + Tap works.
- [ ] Chorus works.
- [ ] Precision Limiter works.
- [ ] GEQ 31 works.
- [ ] FET 76 works.
- [ ] Opto 2A works.

## Monitor / Solo
- [ ] Channel PFL works.
- [ ] Channel AFL works.
- [ ] Bus AFL works.
- [ ] DCA AFL works.
- [ ] Select Follows Solo works.
- [ ] DIM for PFL works.
- [ ] Clear Solo works.
- [ ] Main LR is unaffected by Live32 Solo.

## Hardware routing
- [ ] Main L/R patches to the chosen hardware pair.
- [ ] Monitor L/R patches to a separate hardware pair.
- [ ] Bus direct output patching works.
- [ ] Matrix output patching works.

## Save / reopen
- [ ] Names and colours persist.
- [ ] Links persist.
- [ ] DCA/mute-group membership persists.
- [ ] Scenes recall correctly.
- [ ] Hardware/monitor configuration survives project reopen as expected.
