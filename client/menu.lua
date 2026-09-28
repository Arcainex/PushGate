--[[
    push_gates - the admin menu
    /PushgateDebug
    by XanderP  -  discord.gg/cMqazwj6c7
]]

local open = false

local function gatePayload()
    local g = PG.inReach()
    if not g then return nil end
    return {
        key    = g.key,
        name   = g.name,
        travel = g.def.travel or 5.0,
        axis   = g.def.axis or 'right',
    }
end

--[[ The real list, with the ones that cannot play marked.

     This used to hand over missing = false for everything, which made the
     panel a liar: a clip that does not exist on this build looked identical
     to one that does, and clicking it did nothing with no explanation.

     DoesAnimDictExist is a cheap lookup and does NOT stream the dict in, so
     asking about a dozen of them to draw a list costs nothing. It answers for
     the dictionary rather than the clip, which is the honest half of the
     question - a present dict with a missing clip still only shows up when
     you click it, and the console says so then. ]]
local function animPayload()
    if PG.animList then return PG.animList() end

    local out = {}
    for i, a in ipairs(Config.anim or {}) do
        out[i] = { dict = a.dict, clip = a.clip, missing = not DoesAnimDictExist(a.dict) }
    end
    return out
end

local function openMenu()
    open = true
    SetNuiFocus(true, true)

    SendNUIMessage({
        action = 'menu',
        show = true,
        config = {
            interact      = Config.interact,
            pushScale     = Config.pushScale,
            grabDistance  = Config.grabDistance,
            faceGate      = Config.faceGate,
            promptY       = Config.promptY or 8,
            has_ox   = exports[GetCurrentResourceName()]:TargetRunning('ox'),
            has_qb   = exports[GetCurrentResourceName()]:TargetRunning('qb'),
            has_bs19 = exports[GetCurrentResourceName()]:TargetRunning('bs19'),
        },
        gate  = gatePayload(),
        anims = animPayload(),
        animOn = PG.animIndex(),
    })
end

local function closeMenu()
    open = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'menu', show = false })
end

RegisterNetEvent('push_gates:openMenu', function() openMenu() end)

RegisterCommand('PushgateDebug', function()
    TriggerServerEvent('push_gates:wantMenu')
end, false)

-- lowercase too, nobody types capitals in a console
RegisterCommand('pushgatedebug', function()
    TriggerServerEvent('push_gates:wantMenu')
end, false)

-- keep the gate panel live while the menu is open and you walk about
CreateThread(function()
    local was
    while true do
        Wait(400)
        if open then
            local g = gatePayload()
            local now = g and g.key or ''
            if now ~= was then
                was = now
                SendNUIMessage({ action = 'gate', gate = g })
            end
        else
            was = nil
        end
    end
end)

-- ============================================================
-- NUI
-- ============================================================

RegisterNUICallback('close', function(_, cb)
    closeMenu()
    cb({})
end)

RegisterNUICallback('apply', function(data, cb)
    -- straight to the server, it hands it back out to everyone
    TriggerServerEvent('push_gates:applyConfig', {
        interact      = data.interact,
        pushScale     = tonumber(data.pushScale),
        grabDistance  = tonumber(data.grabDistance),
        faceGate      = data.faceGate and true or false,
        promptY       = tonumber(data.promptY),
    })
    cb({})
end)

RegisterNUICallback('setAnim', function(data, cb)
    local i = tonumber(data.index)
    local a = i and PG.animAt(i)

    if a then
        PG.setAnim(i, a)
        PG.playAnim(a)
        print(('[push_gates] animation set to %s / %s'):format(a.dict, a.clip))
    else
        local want = (Config.anim or {})[i or 0]
        if want then
            print(('[push_gates] %s / %s will not play here - %s')
                :format(want.dict, want.clip,
                    DoesAnimDictExist(want.dict)
                        and 'the dictionary exists but has no clip by that name'
                        or  'that dictionary is not on this build'))
        else
            print('[push_gates] no animation at that index')
        end
    end

    cb({})
end)

RegisterNUICallback('customAnim', function(data, cb)
    local dict = type(data.dict) == 'string' and data.dict:match('^%s*(.-)%s*$') or ''
    local clip = type(data.clip) == 'string' and data.clip:match('^%s*(.-)%s*$') or ''
    if #dict == 0 or #dict > 120 or #clip == 0 or #clip > 120
        or not dict:match('^[%w_@%./%-]+$') or not clip:match('^[%w_@%./%-]+$') then
        cb({ ok = false, message = 'Paste a valid animation dictionary and clip.' })
        return
    end

    Config.anim = Config.anim or {}
    local index = #Config.anim + 1
    Config.anim[index] = { dict = dict, clip = clip }
    local anim = PG.animAt(index)
    if not anim then
        Config.anim[index] = nil
        cb({ ok = false, message = 'That animation is not available on this game build.' })
        return
    end

    PG.setAnim(index, anim)
    PG.playAnim(anim)
    print(('[push_gates] custom animation: %s / %s'):format(dict, clip))
    cb({ ok = true, index = index, message = 'Animation loaded for this session.' })
end)

RegisterNUICallback('gateAction', function(data, cb)
    local g = PG.inReach()
    if not g then cb({}) return end

    local a = data.action


    SendNUIMessage({ action = 'gate', gate = gatePayload() })
    cb({})
end)

--[[ Prints the model lines so you can paste them into config.lua. The live
     changes only last until restart, this is how you keep them. ]]
RegisterNUICallback('dump', function(_, cb)
    print('')
    print('-- push_gates: paste into Config.models')
    for name, def in pairs(Config.models or {}) do
        print(("    ['%s'] = { travel = %.1f, axis = '%s'%s },")
            :format(name, def.travel or 5.0, def.axis or 'right',
                    ''))
    end
    cb({})
end)
