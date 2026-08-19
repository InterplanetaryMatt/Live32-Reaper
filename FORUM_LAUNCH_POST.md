# Suggested REAPER Forum launch post

**Thread title:**

**[BETA] Live32 — virtual 32-channel live console for REAPER | 16 buses, matrices, DCAs, SOF, PFL/AFL**

---

Hi all,

I’ve been working on a slightly ridiculous REAPER experiment that has turned into a fairly substantial project, and I’d love some help testing it.

**Live32 turns REAPER into a virtual digital live console.** REAPER remains the audio/routing engine in the background, while Live32 provides a dedicated console surface and custom JSFX so you can work more like you would on a modern live desk rather than inside a DAW mixer.

**[INSERT FULL-CONSOLE SCREENSHOT HERE]**

The current public-beta build has:

- 32 input channels
- 8 stereo FX returns
- 16 buses
- 8 matrices
- 8 DCAs
- 6 mute groups
- Main LR + dedicated Monitor/Solo bus
- Sends on Faders
- PFL/AFL monitor behaviour that does not interrupt the FOH mix
- odd/even stereo channel and bus linking
- 24 dB/oct channel low-cut
- 4-band input EQ and 6-band bus/Main EQ
- gate/compressor, key filter/source and RTA
- Pre EQ / Post EQ / Pre Fader / Post Fader / Sub Group bus modes
- scenes + recall safe
- hardware-output routing
- Plate, Hall, one-shot Ping-Pong Delay and Chorus
- Precision Limiter, 31-band GEQ, FET 76-style and Opto 2A-style inserts
- a launcher that can build a new console or attach/import an existing multitrack project

The workflow is deliberately inspired by familiar live-console conventions — especially the M32/X32 way of thinking — but this is **not M32-EDIT**, it doesn’t currently control an M32, and the DSP is our own/custom JSFX rather than copied proprietary processing.

One of the things I particularly wanted was proper live-console solo behaviour. Live32 v1.2 has a separate Monitor/Solo path, so pressing SOLO can give the engineer PFL/AFL without muting or changing the Main LR mix. The Routing page lets you patch Main, Monitor, buses and matrices to the hardware outputs exposed by REAPER.

**[INSERT MONITOR OR ROUTING SCREENSHOT HERE]**

### Download

**GitHub:** [ADD REPOSITORY LINK]

Grab the latest `v1.2.1-beta` release ZIP and run `Live32_Launcher.lua` from REAPER’s Action List.

### This is a beta

I’m particularly interested in people trying it on different machines, REAPER versions, interfaces and odd routing situations. If it breaks, please tell me exactly how!

Useful bug reports include:

- OS + REAPER version
- audio interface
- sample rate / buffer
- whether you used New / Attach / Import / Repair
- steps to reproduce
- exact Lua/JSFX error text

There’s also a tester checklist in the repo if anyone is feeling especially destructive.

### AI-assisted development

For transparency: this has been developed iteratively with ChatGPT assisting with the Lua/ReaScript and JSFX implementation/debugging. The console design, workflow, feature requirements and practical testing have been driven around real live-production use. I’m very happy for people to inspect, criticise and improve the code.

### Trademark note

Live32 is an independent project and is not affiliated with or endorsed by Midas or Music Tribe. M32/X32 names are used only to describe workflow inspiration/interoperability goals.

If anyone fancies giving it a go, I’d really value feedback — especially from people who know REAPER scripting/JSFX well and from live engineers who can spot where the console behaviour is wrong.

Thanks!
