-- The type the server has to give CreateVehicleServerSetter for every built-in vehicle that isn't a
-- car ("automobile"), from the FiveM vehicle list (docs.fivem.net/docs/game-references/vehicle-references/vehicle-models).
-- A wrong type makes a broken vehicle, so the server checks against this. Add-on vehicles go in Config.VehicleTypes.

KnownVehicleTypes = {}
KnownTrains = {}

local function add(list, kind, names)
    for name in names:gmatch('%S+') do list[name] = kind end
end

add(KnownVehicleTypes, 'boat', [[
    dinghy dinghy2 dinghy3 dinghy4 dinghy5 jetmax longfin marquis patrolboat predator seashark seashark2 seashark3
    speeder speeder2 squalo suntrap toro toro2 tropic tropic2 tug
]])
add(KnownVehicleTypes, 'submarine', [[avisa kosatka submersible submersible2]])
add(KnownVehicleTypes, 'heli', [[
    akula annihilator annihilator2 buzzard buzzard2 cargobob cargobob2 cargobob3 cargobob4 conada conada2 frogger
    frogger2 havok hunter maverick maverick2 polmav savage seasparrow seasparrow2 seasparrow3 skylift supervolito
    supervolito2 swift swift2 valkyrie valkyrie2 volatus blimp blimp2 blimp3
]])
add(KnownVehicleTypes, 'plane', [[
    alkonost alphaz1 avenger avenger2 avenger3 avenger4 besra bombushka cargoplane cargoplane2 cuban800 dodo duster
    howard hydra jet lazer luxor luxor2 mammatus microlight miljet mogul molotok nimbus nokota pyro raiju rogue
    seabreeze shamal starling streamer216 strikeforce stunt titan tula velum velum2 vestra volatol
]])
add(KnownVehicleTypes, 'bike', [[
    bmx cruiser fixter inductor inductor2 scorcher tribike tribike2 tribike3
    akuma avarus bagger bati bati2 bf400 carbonrs chimera cliffhanger daemon daemon2 deathbike deathbike2 deathbike3
    defiler diablous diablous2 double enduro esskey faggio faggio2 faggio3 fcr fcr2 gargoyle hakuchou hakuchou2 hexer
    innovation lectro manchez manchez2 manchez3 nemesis nightblade oppressor oppressor2 pcj powersurge ratbike reever
    rrocket ruffian sanchez sanchez2 sanctus shinobi shotaro sovereign stryder thrust vader vindicator vortex wolfsbane
    zombiea zombieb policeb policeb2
]])
add(KnownVehicleTypes, 'trailer', [[
    armytanker armytrailer armytrailer2 baletrailer boattrailer boattrailer2 boattrailer3 docktrailer freighttrailer
    graintrailer proptrailer raketrailer tanker tanker2 tr2 tr3 tr4 trailerlarge trailerlogs trailers trailers2
    trailers3 trailers4 trailers5 trailersmall trailersmall2 trflat tvtrailer tvtrailer2
]])
add(KnownTrains, true, [[cablecar freight freight2 freightcar freightcar2 freightcont1 freightcont2 freightgrain metrotrain tankercar]])
