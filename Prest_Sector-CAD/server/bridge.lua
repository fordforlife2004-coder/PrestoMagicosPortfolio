-- Who a player is to the CAD: their name (their character's name when QBCore, Qbox or ESX is running),
-- their roles (ACEs from Config.Roles, plus framework jobs from Config.Jobs) and their license
-- identifier, which ties civilian records to the player who made them. Every framework call is
-- wrapped in pcall, so an update to the framework can't break the CAD: it falls back to FiveM names.

Bridge = {}
local B = Bridge

local framework = nil -- 'qbx', 'qb', 'esx' or nil (standalone)
local qbCore, esx

-- Finds a running framework (when Config.UseFramework is on). Returns its short name, or nil.
function B.init()
    framework, qbCore, esx = nil, nil, nil
    if not Config.UseFramework then return nil end
    if GetResourceState('qbx_core') == 'started' then
        framework = 'qbx'
    elseif GetResourceState('qb-core') == 'started' then
        local ok, core = pcall(function() return exports['qb-core']:GetCoreObject() end)
        if ok and core then qbCore, framework = core, 'qb' end
    elseif GetResourceState('es_extended') == 'started' then
        local ok, shared = pcall(function() return exports.es_extended:getSharedObject() end)
        if ok and shared then esx, framework = shared, 'esx' end
    end
    return framework
end

function B.framework() return framework end

-- The player's character from the framework: { name, job, onDuty }, or nil.
local function character(src)
    if framework == 'qbx' or framework == 'qb' then
        local ok, player = pcall(function()
            if framework == 'qbx' then return exports.qbx_core:GetPlayer(src) end
            return qbCore.Functions.GetPlayer(src)
        end)
        local pd = ok and type(player) == 'table' and player.PlayerData or nil
        if type(pd) ~= 'table' then return nil end
        local info = type(pd.charinfo) == 'table' and pd.charinfo or {}
        local job = type(pd.job) == 'table' and pd.job or {}
        return { name = ('%s %s'):format(info.firstname or '', info.lastname or ''), job = job.name, onDuty = job.onduty }
    elseif framework == 'esx' then
        local ok, xPlayer = pcall(function() return esx.GetPlayerFromId(src) end)
        if not ok or type(xPlayer) ~= 'table' then return nil end
        local okName, name = pcall(function() return xPlayer.getName() end)
        local job = type(xPlayer.job) == 'table' and xPlayer.job or {}
        -- ESX has no duty switch of its own; servers that add one usually set job.onDuty.
        return { name = okName and name or nil, job = job.name, onDuty = job.onDuty }
    end
    return nil
end

-- The name the CAD shows for a player.
function B.name(src)
    local c = character(src)
    if c and type(c.name) == 'string' then
        local name = CAD.text(c.name, 40)
        if name ~= '' then return name end
    end
    local name = CAD.text(GetPlayerName(src) or '', 40)
    return name ~= '' and name or ('Player ' .. tostring(src))
end

-- The player's CAD roles: { police = true, ... }.
function B.roles(src)
    local roles = {}
    for role, ace in pairs(Config.Roles or {}) do
        if type(ace) == 'string' and ace ~= '' and IsPlayerAceAllowed(src, ace) then roles[role] = true end
    end
    local c = character(src)
    local jobRoles = c and type(c.job) == 'string' and Config.Jobs and Config.Jobs[c.job]
    if jobRoles and (not Config.JobsNeedDuty or c.onDuty ~= false) then
        for _, role in ipairs(jobRoles) do roles[role] = true end
    end
    return roles
end

-- The player's 'license:...' identifier, or nil.
function B.license(src)
    local id = GetPlayerIdentifierByType and GetPlayerIdentifierByType(src, 'license') or nil
    if id then return id end
    for _, ident in ipairs(GetPlayerIdentifiers(src) or {}) do
        if type(ident) == 'string' and ident:sub(1, 8) == 'license:' then return ident end
    end
    return nil
end
