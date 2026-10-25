# Preston Iowa Police v2

Spawn and style Iowa patrol vehicles: Iowa State Patrol with tan and black paint, gold pearl and blue-on-white plates, plus a County Sheriff preset. Plates carry the unit number, like `ISP 101`. Standalone (no QBCore or ESX). The server checks who may use it, spawns the cars itself, and sets the plates.

## What v2 fixes from v1

| v1 | v2 |
| --- | --- |
| Anyone could spawn police cars. | Only players with the `iowapolice.use` ACE (your police whitelist) can spawn or style them. |
| `/isp` waited forever if the model wasn't loaded, and every car had the plate `ISP001`. | The model is checked first, with a clear message if it isn't installed. Plates use the unit number you type (`/isp 101` gives `ISP 101`), or one from your server ID. |
| It turned on extras 0 to 12 blindly, including ones the car doesn't have, and that also repaired all damage. | Only extras the car really has are touched, without repairing damage. Each department can turn on every extra or list exactly which ones. |
| `/iowaskin` worked from any seat and set `IOWA PD` plates. | Driver only. You choose the department and unit number. |
| One hard-coded department. | Departments live in the config (Iowa State Patrol and County Sheriff to start). Each gets its own command, and you can add more. |
| Cars were spawned in the player's own game and piled up. | The server creates the car in your world instance, and your game gets you in once the car arrives. There's a cooldown. Your last car is removed when you spawn another or leave, but never while a partner (or a suspect in the back) is in it. |

## Commands

| | |
| --- | --- |
| `/isp 101` | Spawn an Iowa State Patrol car, plate `ISP 101` |
| `/sheriff 12` | Spawn a County Sheriff car, plate `SO 012` |
| `/iowaskin` | Style the car you're driving as ISP (plate from your server ID) |
| `/iowaskin sheriff 7` | Style it as County Sheriff unit 7 |
| `/iowahelp` | List the commands in chat |

## Install

1. Put `preston-iowapolice` in your `resources` folder.
2. Add it to `server.cfg` and grant your police players the ACE:

```cfg
ensure preston-iowapolice
add_ace group.police iowapolice.use allow
add_principal identifier.license:THEIR_LICENSE group.police
```

3. Optional: if you have an add-on Tahoe, put its spawn name in `Config.Departments.isp.model` in [`config.lua`](config.lua).

## Adding a department

```lua
Config.Departments.dsm = {
    command = 'dsm',             -- /dsm 300
    label = 'City Police',
    model = 'police',
    vehicleType = 'automobile',  -- or 'bike', 'boat', 'heli', 'plane'; must match the model
    plate = 'DSM',               -- 1 to 3 letters; "DSM 300"
    colors = { 111, 0 },         -- white and black (nil keeps the car's own paint)
    plateStyle = 4,
    livery = 1,                  -- optional
    extras = { [1] = true, [2] = false },  -- or 'all'
}
```

Mistakes in a department are printed in the server console on start: a long plate prefix, two departments with the same command, or a bad plate style. If `vehicleType` doesn't match the model (say, a helicopter left as `automobile`), the spawn command says so instead of spawning a broken vehicle.

## Tests

```bash
lua tests/iowa_spec.lua
lua tests/server_spec.lua
lua tests/client_spec.lua
```

- `iowa_spec.lua` tests unit numbers, plates and the config checker.
- `server_spec.lua` runs the server in a fake server. It covers:
  - the whitelist, unit plates, the cooldown and unknown departments
  - the world instance, and replacing your last car but keeping it while a partner is in it
  - cars that fail or never arrive, and old car handles never being reused
  - the `/iowaskin` driver and slow-down checks
- `client_spec.lua` runs the game script in a fake game. It covers:
  - getting in once the car arrives, and reporting one that doesn't
  - the ISP look, departments without paint, listed extras and both kinds of livery
  - the installed-model and vehicle-type checks
  - `/iowaskin` argument order

---

Made by Preston D. Standalone, free to use on your server.
