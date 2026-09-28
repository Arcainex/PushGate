--[[
    push_gates - server
    by XanderP  -  discord.gg/cMqazwj6c7

    Holds one number per gate (how open it is) and who is pushing it.
    No database, nothing saved, it all resets on restart.
]]

local gates  = {}   -- [key] = -1..1, matching the client rail movement
local holder = {}   -- [key] = who has it
local held   = {}   -- [src] = key, so we can clean up on disconnect
local lastAt = {}   -- [src] = last push, rate limit
local lease = {}    -- [key] = last accepted activity
local session = {}  -- [key] = claim generation; rejects stale movement packets
local nextSession = 0

--[[ The key is model:x:y:z with the coords rounded, so we can read the gates
     map position back out of it. Thats how we check someone claiming a gate
     is actually stood near one instead of grabbing every gate on the map
     from spawn. ]]
local function keyCoords(key)
    local _, x, y, z = key:match('^(-?%d+):(-?%d+):(-?%d+):(-?%d+)$')
    if not x then return nil end
    return vector3(tonumber(x) + 0.0, tonumber(y) + 0.0, tonumber(z) + 0.0)
end

local function nearGate(src, key)
    local at = keyCoords(key)
    if not at then return false end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end

    -- generous on purpose. the key is where the gate STARTS and it might be
    -- slid several metres from there, plus gates are wide and the rounding
    -- costs another metre. the client does the tight check
    return #(GetEntityCoords(ped) - at) < 30.0
end

--[[ Nobody has the pushgates.admin ace on a fresh install, so on its own
     that locked everyone out including the owner. Now we try a few things,
     and if none of them work we TELL you which identifier to add instead of
     just saying no. ]]
local function isAdmin(src)
    if src == 0 then return true, 'console' end

    if IsPlayerAceAllowed(src, Config.adminAce or 'pushgates.admin') then
        return true, 'ace'
    end

    -- server owners and admins nearly always have this one already
    if Config.useCommandAce ~= false and IsPlayerAceAllowed(src, 'command') then
        return true, 'command ace'
    end

    for _, id in ipairs(Config.admins or {}) do
        for i = 0, GetNumPlayerIdentifiers(src) - 1 do
            if GetPlayerIdentifier(src, i) == id then return true, 'config list' end
        end
    end

    --[[ Whatever admin system the server already runs. All pcall'd because
         were guessing at export names on resources that might not be there,
         and a wrong guess shouldnt error. ]]
    if Config.useFrameworkAdmin ~= false then
        if GetResourceState('bs_admin') == 'started' then
            local ok, yes = pcall(function() return exports.bs_admin:IsAdmin(src) end)
            if ok and yes then return true, 'bs_admin' end
        end

        if GetResourceState('es_extended') == 'started' then
            local ok, yes = pcall(function()
                local xPlayer = exports.es_extended:getSharedObject().GetPlayerFromId(src)
                local g = xPlayer and xPlayer.getGroup()
                return g == 'admin' or g == 'superadmin' or g == 'mod'
            end)
            if ok and yes then return true, 'esx group' end
        end

        if GetResourceState('qb-core') == 'started' then
            local ok, yes = pcall(function()
                return exports['qb-core']:GetCoreObject().Functions.HasPermission(src, 'admin')
            end)
            if ok and yes then return true, 'qb permission' end
        end
    end

    return false
end

--[[ Told, not just refused. Being locked out of your own admin menu with no
     idea why is miserable, so we print the exact line to run. ]]
local function refuse(src)
    local lic = 'license:????'
    for i = 0, GetNumPlayerIdentifiers(src) - 1 do
        local id = GetPlayerIdentifier(src, i)
        if id and id:sub(1, 8) == 'license:' then lic = id break end
    end

    local ace = Config.adminAce or 'pushgates.admin'

    TriggerClientEvent('chat:addMessage', src, {
        color = { 255, 120, 120 },
        args = { 'push_gates', 'admin only - check the server console, it says how to add yourself' },
    })

    print('')
    print(('[push_gates] %s tried to open the menu and isnt an admin.'):format(
        GetPlayerName(src) or src))
    print('[push_gates] add them with either of these in server.cfg:')
    print(('    add_ace identifier.%s %s allow'):format(lic, ace))
    print(('    -- or put "%s" in Config.admins'):format(lic))
    print('')
end

local function releaseFor(src)
    local key = held[src]
    if not key then return end
    held[src] = nil
    if holder[key] == src then
        holder[key] = nil
        lease[key] = nil
    end
end

-- ============================================================

RegisterNetEvent('push_gates:claim', function(key, requestId)
    local src = source
    if type(key) ~= 'string' or #key > 64 then return end
    if type(requestId) ~= 'number' then return end
    if not nearGate(src, key) then
        TriggerClientEvent('push_gates:denied', src, key, 'Move closer to the gate', requestId)
        return
    end

    -- one person per gate, two people pushing opposite ways would just be
    -- whichever packet lands last and the gate shakes
    local owner = holder[key]
    if owner and owner ~= src and GetPlayerName(owner)
        and GetGameTimer() - (lease[key] or 0) < 5000 then
        TriggerClientEvent('push_gates:denied', src, key, 'Someone is already pushing this gate', requestId)
        return
    end

    if owner and owner ~= src then releaseFor(owner) end
    releaseFor(src)
    nextSession = nextSession + 1
    holder[key], held[src] = src, key
    session[key] = nextSession
    lease[key] = GetGameTimer()
    TriggerClientEvent('push_gates:claimed', src, key, gates[key] or 0.0, session[key], requestId)
end)

RegisterNetEvent('push_gates:push', function(key, ratio, claimId)
    local src = source
    if type(key) ~= 'string' or #key > 64 then return end
    if holder[key] ~= src or session[key] ~= claimId then return end
    if not nearGate(src, key) then
        releaseFor(src)
        TriggerClientEvent('push_gates:denied', src, key, 'Move closer to the gate',
            nil, gates[key] or 0.0, claimId)
        return
    end

    ratio = tonumber(ratio)
    if not ratio or ratio ~= ratio or ratio == math.huge or ratio == -math.huge then return end
    if ratio < -1.0 then ratio = -1.0 elseif ratio > 1.0 then ratio = 1.0 end

    local now = GetGameTimer()
    if now - (lastAt[src] or 0) < 40 then return end
    lastAt[src] = now
    lease[key] = now

    gates[key] = ratio
    TriggerClientEvent('push_gates:sync', -1, key, ratio)
end)

RegisterNetEvent('push_gates:release', function(key, ratio, claimId)
    local src = source
    if type(key) ~= 'string' or #key > 64 then return end
    if holder[key] ~= src or session[key] ~= claimId then return end

    ratio = tonumber(ratio)
    if ratio and ratio == ratio and ratio ~= math.huge and ratio ~= -math.huge then
        if ratio < -1.0 then ratio = -1.0 elseif ratio > 1.0 then ratio = 1.0 end
        gates[key] = ratio
        TriggerClientEvent('push_gates:sync', -1, key, ratio)
    end

    releaseFor(src)
end)

RegisterNetEvent('push_gates:keepalive', function(key, claimId)
    local src = source
    if type(key) ~= 'string' or #key > 64 then return end
    if holder[key] ~= src or session[key] ~= claimId then return end
    if not nearGate(src, key) then
        releaseFor(src)
        TriggerClientEvent('push_gates:denied', src, key, 'Move closer to the gate',
            nil, gates[key] or 0.0, claimId)
        return
    end
    lease[key] = GetGameTimer()
end)

CreateThread(function()
    while true do
        Wait(2500)
        local now = GetGameTimer()
        for key, src in pairs(holder) do
            if now - (lease[key] or 0) > 5000 or not GetPlayerName(src) then
                releaseFor(src)
            end
        end
    end
end)



RegisterNetEvent('push_gates:request', function()
    local src = source
    local open = {}
    for k, v in pairs(gates) do
        if math.abs(v) > 0.0005 then open[k] = v end
    end
    TriggerClientEvent('push_gates:all', src, open)
end)

-- ============================================================
-- ADMIN MENU
-- ============================================================

RegisterNetEvent('push_gates:wantMenu', function()
    local src = source
    local ok, how = isAdmin(src)
    if not ok then refuse(src) return end

    print(('[push_gates] %s opened the menu (%s)'):format(GetPlayerName(src) or src, how))
    TriggerClientEvent('push_gates:openMenu', src)
end)

--[[ Config changes from the menu go out to everyone, not just whoever opened
     it. Half the server on one setting and half on another would be a
     nightmare to work out later. Not saved though, its gone on restart -
     use the print button and put it in config.lua to keep it. ]]
RegisterNetEvent('push_gates:applyConfig', function(c)
    local src = source
    if not isAdmin(src) then return end
    if type(c) ~= 'table' then return end

    local clean = {}

    local ok = { hold = true, ox = true, qb = true, bs19 = true, auto = true }
    if ok[c.interact] then clean.interact = c.interact end

    local n = tonumber(c.pushScale)
    if n then clean.pushScale = math.max(0.1, math.min(3.0, n)) end

    n = tonumber(c.grabDistance)
    if n then clean.grabDistance = math.max(0.5, math.min(8.0, n)) end

    n = tonumber(c.promptY)
    if n then clean.promptY = math.max(0, math.min(60, n)) end

    clean.faceGate      = c.faceGate and true or false

    TriggerClientEvent('push_gates:config', -1, clean)

    print(('[push_gates] %s changed the config: grab=%s scale=%.2f dist=%.1f')
        :format(GetPlayerName(src) or src, clean.interact or '-',
                clean.pushScale or 0, clean.grabDistance or 0))
end)

AddEventHandler('playerDropped', function()
    local src = source
    releaseFor(src)
    lastAt[src] = nil
end)
