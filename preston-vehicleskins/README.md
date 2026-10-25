# Preston Vehicle Skins v2

Liveries, extras, paint, plates and performance tuning for the car you're driving, plus `/spawnskin` to spawn a car with a livery. Standalone (no QBCore or ESX). Every change goes through the server first, which checks the command's permission, that you're the driver and that the values make sense.

## What v2 fixes from v1

| v1 | v2 |
| --- | --- |
| `/tune` put the last visual part on every mod slot from 0 to 16, so cars got random spoilers, bumpers and skirts. It set turbo like a level, so turbo never actually turned on. It also made the tires bulletproof. | `/tune` upgrades performance parts only: engine, brakes, transmission, suspension and armor. Turbo is switched on the right way, and tires and windows are left alone. The list is in the config. |
| `/randomlivery` errored on cars with no liveries. | It says the car has no liveries. With a choice, it never picks the livery you already have. |
| Liveries were counted from 0, and only one of the two kinds of livery worked. Many add-on cars use the other kind (mod-kit liveries). | Liveries are numbered from 1 and both kinds work. `/liveries` shows how many there are and which one you're on. |
| `/extra` repaired all damage every time, which worked as a free repair. | Extras toggle without repairing the car. `/extras` lists which extras the car has. |
| `/spawnskin` waited forever on a misspelled model, spawned the car in the player's own game, and had no limits. | The model is checked first. The server creates the car in your world instance with a cooldown, and blocked models are matched by the game's model ID. Your game gets you in once the car arrives, then sets the livery. Your last car is removed unless someone else is in it. |
| Anyone could change anything, even as a passenger. | Only the driver can make changes, and each command can need an ACE. Custom plates and `/tune` are limited by default. |
| The manifest and the code were in one file. | A normal resource layout with tests. |

New in v2: `/color`, `/plate` and `/extras`.

## Commands

| | |
| --- | --- |
| `/spawnskin police3 2` | Spawn a car with livery 2 |
| `/liveries` | How many liveries the car has, and which one it's on |
| `/setlivery 3` | Set livery 3 |
| `/randomlivery` | A random different livery |
| `/extras` | Which extras the car has, on or off |
| `/extra 1` | Turn extra 1 on or off |
| `/color 27 0` | Paint: primary and secondary (0 to 160; one number paints both) |
| `/plate PRESTON` | Plate text, up to 8 letters and numbers (needs `vehicleskins.plate`) |
| `/tune` | Best engine, brakes, transmission, suspension and armor, plus turbo (needs `vehicleskins.tune`) |
| `/vehicleskins` | List the commands in chat |

## Install

1. Put `preston-vehicleskins` in your `resources` folder.
2. Add `ensure preston-vehicleskins` to `server.cfg`.
3. Grant the limited commands to whoever should have them:

```cfg
add_ace group.vip vehicleskins.plate allow
add_ace group.vip vehicleskins.tune allow
# or everything:
add_ace group.admin vehicleskins allow
```

Permissions per command, the tune list, the spawn cooldown and blocked models are in [`config.lua`](config.lua). For add-on vehicles that aren't cars, add their type to `Config.VehicleTypes` (for example `{ policeheli = 'heli' }`) so `/spawnskin` spawns them as the right kind of vehicle.

## Tests

```bash
lua tests/skins_spec.lua
lua tests/server_spec.lua
lua tests/client_spec.lua
```

- `server_spec.lua` runs the server in a fake server. It covers:
  - the driver-only rule, number ranges, and permissions for plates and tune
  - cleaning of odd values and the rate limit
  - `/spawnskin`: world instance, blocked models by model ID, vehicle types, keeping your last car when someone else is in it, and cars that never arrive
  - old car handles never being reused
- `client_spec.lua` runs the game script in a fake game. It covers:
  - both kinds of livery, and random livery on a car without any
  - extras not repairing damage, paint and plates
  - `/tune` touching only performance parts, turning turbo on correctly, and refusing cars with no mod kit
  - getting in after `/spawnskin`, and reporting a car that never arrives
  - long messages being split for the game
  - nothing changing without control of the car

---

Made by Preston D. Standalone, free to use on your server.
