# Preston Vehicle Spawn v2

`/car <model>` to spawn any vehicle and `/dv` to delete it. Standalone (no QBCore or ESX). The server does the spawning and decides who may spawn what.

## What v2 fixes from v1

| v1 | v2 |
| --- | --- |
| The resource was only a manifest. Its `client.lua` was missing, so it never started. | A complete resource with config, server, client and tests. |
| Spawning (as in the other v1 scripts) waited forever on a misspelled model and spawned the car in the player's own game. | The model is checked first, with a clear message if it doesn't exist. The server creates the car in your world instance, and your game puts you in the driver seat once the car has arrived. |
| Anyone could spawn anything, as often as they liked, including tanks and jets. | A cooldown between spawns, a starting list of blocked models (tanks, armed jets and helicopters, Arena War vehicles, Oppressors and the like) and an optional ACE to limit who can spawn. Blocked models are matched by the game's model ID, so a different name for the same model doesn't get through. Staff skip the cooldown and the blocked list. |
| Cars piled up around the map. | Your last spawned car is removed when you spawn another or leave the server, unless someone else is in it. |
| No way to delete a car. | `/dv` deletes your own car when you're in it or standing next to it, even if another car is closer. Staff can delete any car. |

The server also checks that each model is spawned as the right kind of vehicle (car, bike, boat, helicopter, plane, submarine or trailer). A vehicle spawned as the wrong kind breaks for everyone nearby. Built-in vehicles are already listed. For add-on vehicles that aren't cars, add their type to `Config.VehicleTypes`, for example `{ policeheli = 'heli' }`.

## Commands

| | |
| --- | --- |
| `/car adder` | Spawn a vehicle and get in |
| `/dv` | Delete the vehicle you spawned (the one you're in, or the closest within 6 m) |

## Install

1. Put `preston-vehiclespawn` in your `resources` folder.
2. Add `ensure preston-vehiclespawn` to `server.cfg`.
3. Optional, for staff (no cooldown, blocked models, `/dv` on any car):

```cfg
add_ace group.admin vehiclespawn.staff allow
```

To limit `/car` to some players, set `Config.AcePermission = 'vehiclespawn.use'` and grant it the same way. Cooldown, plate text, blocked models and the `/dv` distance are in [`config.lua`](config.lua).

## Tests

```bash
lua tests/rules_spec.lua
lua tests/server_spec.lua
```

The server test runs `server/main.lua` in a small fake server. It covers:
- the cooldown, staff rules and ACE limits
- blocked models, including another name with the same model ID
- vehicle types
- the player's world instance
- refusing to spawn while sitting in someone else's car
- replacing your last car, and keeping it when someone else is in it
- `/dv` ownership, distance and driver checks, and finding your own car on foot
- cars that never reach the player
- cleanup when a player leaves

---

Made by Preston D. Standalone, free to use on your server.
