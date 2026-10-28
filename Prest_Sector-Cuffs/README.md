# Prest_Sector Cuffs

Realistic handcuffing for FiveM. The cuffs are GTA's own handcuff model, hung on each cuffed player's wrists so their hands sit inside the cuffs, and everyone nearby sees them. Standalone (no QBCore or ESX). The server checks every arrest.

## What it does

- **Cuffs you can see.** The game's handcuffs (`p_cs_cuffs_02_s`) hang from the cuffed player's left-hand bone, placed around both wrists.
  - There's one placement for hands behind the back and one for hands in front.
  - Every nearby player's game draws them. They move with the hands while the player walks, and stay on through falls and respawns.
  - They hide when the player goes invisible.
  - No cuffs are left floating when someone leaves or the script stops.
- **A real arrest.**
  - **Behind the back:** GTA Online's paired arrest. The officer takes the suspect's wrists from behind, and the cuffs close at the end (about 4 seconds).
  - **In front:** face to face. The suspect turns to the officer, and the cuffs go on in front.
  - `/cuff` on its own picks the side from where the officer stands.
  - The suspect is held against the officer for a moment as it starts, then can try to pull away. If they get out of reach before the cuffs close, they stay free. Set `Config.SuspectCanPullAway = false` to hold them still for the whole arrest.
  - Nobody is cuffed, held or lined up through a wall.
- **Being cuffed.**
  - The arms stay in the cuffed pose, and it comes back after a fall.
  - No weapons, punching, aiming, jumping, cover, getting into vehicles or phone. A cuffed player in the front seat can't shuffle over and drive.
  - Walking is allowed. Sprinting is off by default.
  - **Leaving isn't a way out.** A cuffed player who disconnects and comes back within 10 minutes (`Config.KeepCuffsMinutes`) is cuffed again.
- **Escort.**
  - `/escort` holds a cuffed player at your side by the arm. Their legs walk or run with you, and your hand rests on their arm.
  - You can't get into a vehicle while holding someone. Use `/putin`, or let go.
  - If you end up far apart (you died and respawned, say) or you drive off, you lose your hold. They're never pulled across the map.
- **Vehicles.**
  - `/putin` seats the player you're holding in a back seat of the nearest vehicle. They climb in, or are put straight in if a door is blocked. They're never put into a car that has driven off, or one someone else is driving.
  - `/takeout` brings them out, and you have them by the arm again.
- **Checked by the server.** These are all checked or decided by the server:
  - the police permission (an ACE)
  - being within reach in the same world instance
  - one arrest at a time per officer and per suspect, and a cooldown
  - who is cuffed and who is held

  Who is cuffed and who is held live in GlobalState, which only the server can write. Stopping or restarting the script takes everyone's cuffs off, so nobody is left stuck.
- **`/cuffadjust`.** Fine-tune where the cuffs sit, in game, with the arrow keys, then paste the line it prints into the config.

What a cuffed player can't do (shoot, sprint, drive) is enforced in their own game, like in every FiveM script, so a cheat menu could lift it there. Everything they do to other players still goes through the server.

## Commands

| | |
| --- | --- |
| `/cuff` | Cuff the nearest player: in front if you're facing them, behind the back if you're behind them |
| `/cuff front`, `/cuff rear` | Pick the style yourself |
| `/uncuff` | Take the cuffs off the nearest cuffed player |
| `/escort` | Take the nearest cuffed player by the arm, or let go |
| `/putin` | Seat the player you're holding in the nearest vehicle |
| `/takeout` | Bring a cuffed player out of the nearest vehicle |
| `/cuffadjust [rear\|front]` | Line the cuffs up on your own wrists (needs `cuffs.adjust`) |
| `/cuffhelp` | List the commands in chat |

Players can bind keys for **cuff or uncuff the nearest player** and **escort** in **Settings → Key Bindings → FiveM**. There are no default keys, so nothing clashes with your other scripts. You can set defaults in `Config.Keys`.

## Install

1. Put `Prest_Sector-Cuffs` in your `resources` folder.
2. It needs OneSync (on by default on current servers). Add it to `server.cfg` and grant your police the ACE:

```cfg
ensure Prest_Sector-Cuffs
add_ace group.police cuffs.use allow
add_ace group.admin cuffs.adjust allow
add_principal identifier.license:THEIR_LICENSE group.police
```

Everything else is in [`config.lua`](config.lua): reach, cooldown, sprinting while cuffed, pulling away, keeping cuffs on rejoin, and the cuff positions and animations. Mistakes in it are printed in the server console when the script starts.

## Lining up the cuffs

The cuffs start where several open-source FiveM police scripts put this model, behind the back and in front. Character models differ, so check them on yours:

1. Run `/cuffadjust rear` (or `front`). Your character takes the cuffed pose, with the cuffs on (only you see them).
2. Arrow keys move the cuffs left/right and forward/back, and Page Up/Page Down move them up and down.
   - Hold **Shift** to turn them instead, and **Ctrl** for small steps.
   - Look around with the mouse to see your wrists from every side.
3. Press **Enter**. Chat and the F8 console show a line like `offset = { -0.055, 0.060, 0.040 }, rotation = { 265.0, 155.0, 80.0 },`. Paste it over that style's `offset` and `rotation` in `config.lua`.
4. **Backspace** stops. Restarting the script while adjusting is fine too: you're unfrozen.

The F8 console also shows how long the cuff and uncuff animations really are. If the cuffs close noticeably before or after the hands meet, set `Config.Animations.cuff.seconds` to match.

## For other scripts

- **Server:**
  - `exports['Prest_Sector-Cuffs']:IsCuffed(id)` returns `true` and the style, or `false`.
  - `exports['Prest_Sector-Cuffs']:Uncuff(id)` takes the cuffs off at once, for a jail or an admin menu.
- **Player's game:** `exports['Prest_Sector-Cuffs']:IsCuffed()`.
- **Either side:**
  - `GlobalState['prestSectorCuffs:' .. id]` is the style a player is wearing (`'rear'` or `'front'`), or `nil`.
  - `GlobalState['prestSectorEscort:' .. id]` is the server ID of the officer holding them.
  - For example, a phone or inventory script can refuse to open while cuffed. Only the server can change these.

## Tests

```bash
lua tests/cuffs_spec.lua
lua tests/server_spec.lua
lua tests/client_spec.lua
```

- `cuffs_spec.lua` tests:
  - styles and player IDs
  - picking who you mean
  - front or behind from where you stand
  - `/cuffadjust`'s nudges and printed line
  - the config checker
- `server_spec.lua` runs the server in a fake server. It covers:
  - the permission, reach and instance checks, and IDs from the network that aren't whole numbers
  - the arrest finishing only after its animation; a suspect who pulls away or jumps into a car stays free
  - one arrest at a time, nobody joining in on either side, and the cooldown in milliseconds
  - players leaving mid-arrest, and cuffs kept when a cuffed player leaves and rejoins
  - escort, and losing the hold when apart or driving
  - `/putin`: never the driver seat, a taken seat, or a getaway car; one at a time
  - `/takeout`, which never steals another officer's hold
  - stopping and restarting the script
- `client_spec.lua` runs the game scripts in a fake game. It covers:
  - the cuffs drawn on the right bone at the right spot, local to each game
  - new cuffs after a respawn, hidden with the player, and removed when out of view or uncuffed
  - what a cuffed player can't do, with the pose and the handcuff flag coming back
  - being walked along, but never through a wall or from far away
  - the officer's commands picking the right player and seat
  - the arrest line-up, and pulling away
  - climbing in and out of vehicles, and never being warped into one that left
  - `/cuffadjust`, and stopping the script mid-adjust or mid-arrest

The tests run outside the game, so they check the logic, not how it looks. Check the fit in game with `/cuffadjust`.

---

Made by Preston D. Standalone, free to use on your server.
