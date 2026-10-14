# Impact Frames 1.2.1

by: Zarianna (100% vibe coded)

<img width="514" height="641" alt="Screenshot 2026-10-13 220854" src="https://github.com/user-attachments/assets/1c34b0e5-ea6b-4cb7-93e5-69c86f1362f2" />

[Final Heaven Demo]([https://youtu.be/1FU9Q8cAnL0](https://youtu.be/1FU9Q8cAnL0))

Weapon-skill animation freezes with synchronized WS visuals. Includes 177 exported timing profiles as the defaults.

## Install

Create a impactframes folder in your Ashita `addons` folder. `impactframes.lua` must be directly inside `addons/impactframes/`. Then run `/addon load impactframes`.


The prebuilt 32-bit native DLL is included and must be kept alongside the Lua files.

## Settings

Type `/if` to open ImpactFrames settings.

- **Enable Impact Frames** turns animation freezes and their corresponding visuals on or off.
- **Impact Frames for other player characters** applies the same behavior when another player performs a supported WS.
- **Custom timing offsets and overrides** opens the searchable WS selector and per-WS controls.

ImpactFrames comes with pre-made timings ready to go. **Race**, above the WS selector, chooses **Global (all races)** or one of the eight race/gender variants. Specific overrides apply to the race of the player performing the WS; races without a specific override will use global timings. This selector does not change anyone's visible race.

For a custom override, edit each hit's time and freeze duration. Valid changes will auto-save. Hit times must increase from previous hit #, and up to eight impacts are supported. Each successful freeze shifts subsequent impacts by its duration.

**Disable ImpactFrames for this weaponskill** affects the selected WS and race selected (or global if selected). A specific race's switch will be used over the global switch. **Reset to impactframes default value** restores that WS's exported timings and enable state for the selected race without changing other skills or races. A WS with no exported profile runs only after you create your own override.

Settings and overrides are shared by all characters in `config/addons/impactframes/release/settings.lua`.

## Notes

The addon reads incoming WS results and applies effects locally. It does not send or modify game packets.

If you are hit by a monster with a knockback effect against your own character, Impact Frames immediately releases your active freeze and discards the rest of your queued WS freezes. Knockback against other players does not interrupt their Impact Frames timelines. The knockback packet is passed through unchanged.

The native helper includes MinHook; its license is in `native/MinHook-LICENSE.txt`.
