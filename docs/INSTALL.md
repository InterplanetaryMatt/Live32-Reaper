# Installation and First Run

## 1. Put Live32 somewhere permanent

Extract the release ZIP. Do not run the scripts directly from a temporary download folder if you plan to keep using the project; Live32 Setup copies its bundled JSFX from the folder containing the scripts.

## 2. Add the Launcher to REAPER

In REAPER:

1. Open **Actions → Show action list**.
2. Choose **New action → Load ReaScript**.
3. Select `Live32_Launcher.lua` from the Live32 folder.
4. Optionally assign it a keyboard shortcut or toolbar button.

## 3. Choose a workflow

### New Console
Use for a blank project. Live32 builds the entire console architecture.

### Attach Project
Use selected existing REAPER tracks as Live32 input channels. Existing media and track structure stay in place while Live32 adds its console infrastructure.

### Import Multitrack
Use for a clean virtual-soundcheck style workflow. Selected media is copied into fresh Live32 input tracks while the original source tracks are retained.

### Training Template
Builds a labelled live-show starting point ready for stems.

## 4. Route Main and Monitor outputs

Open **ROUTING → MAIN/MON**.

For a proper FOH-style setup, assign:

- **Main L/R** to the PA/FOH output pair.
- **Monitor L/R** to a different output pair for headphones/control-room monitors.

## 5. Test Solo safely

Start playback at a low level. Press SOLO on a channel. The Main LR mix should continue normally while the selected source is heard on the Monitor/Solo path.

Use the **MONITOR** page to switch channel solos between PFL and AFL and configure bus/DCA AFL behaviour.

## Updating during beta

Until ReaPack distribution is available, beta updates may include replacement Lua/JSFX files. Read the release notes before dropping a new build into an existing project, because some versions alter the project/DSP architecture.
