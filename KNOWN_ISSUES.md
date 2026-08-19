# Known Issues / Beta Notes

Live32 is currently a public beta. The following areas especially need community testing.

- **Cross-platform testing:** Windows/macOS/Linux behaviour has not yet been exhaustively validated across REAPER versions and graphics configurations.
- **Older-project repair:** Repair/complete has been improved substantially, but projects created with much older development builds may expose edge cases. Back up the project first.
- **Window size:** The console UI currently targets a large desktop display and is not yet responsive for very small screens.
- **Hardware output names:** Routing depends on the outputs exposed by the currently selected REAPER audio device.
- **Monitor routing:** A separate engineer monitor output requires Monitor L/R to be explicitly assigned to a physical output pair.
- **Manufacturer remote control:** Live32 does not currently communicate with a physical M32/X32 or M32-EDIT.
- **ReaPack:** A ReaPack repository is planned after the first public-beta feedback cycle.
- **DSP intent:** Live32 processors are workflow-oriented original implementations; they are not component-level emulations of proprietary Midas, UREI, Teletronix or other hardware/software algorithms.

If something fails, please open a bug report with the exact error message and reproduction steps.
