-- Vehicle Trust System (Server)
-- Drop-in replacement for your server.lua

local prefix = '^0[^6VehicleTrustSystem^0] '

---------------------------------------------------------------------
-- Utilities
---------------------------------------------------------------------

local function primaryId(src)
    local ids = GetPlayerIdentifiers(src)
    if ids and ids[1] then return ids[1] end
    return nil
end

local function readConfig()
    local raw = LoadResourceFile(GetCurrentResourceName(), "whitelist.json")
    if not raw or raw == "" then return {} end
    local ok, decoded = pcall(json.decode, raw)
    if not ok or type(decoded) ~= "table" then return {} end
    return decoded
end

local function writeConfig(cfg)
    SaveResourceFile(GetCurrentResourceName(), "whitelist.json", json.encode(cfg, { indent = true }), -1)
end

local function upcase(s) return (s and string.upper(s)) or s end

-- Return: ownerIdentifier or nil if none
local function findOwnerOfVehicle(cfg, vehicleSpawn)
    local want = upcase(vehicleSpawn)
    for identifier, vehicles in pairs(cfg) do
        for _, v in ipairs(vehicles) do
            if upcase(v.spawncode) == want and v.owner == true then
                return identifier
            end
        end
    end
    return nil
end

-- Ensure table for an identifier
local function ensureList(cfg, identifier)
    if not cfg[identifier] then cfg[identifier] = {} end
    return cfg[identifier]
end

-- Find spawncode in a list (case-insensitive). Returns index or nil.
local function findVehicleIndex(list, vehicleSpawn)
    local want = upcase(vehicleSpawn)
    for i, v in ipairs(list) do
        if upcase(v.spawncode) == want then
            return i
        end
    end
    return nil
end

-- Upsert a vehicle entry in a list
local function upsertVehicle(list, vehicleSpawn, props)
    local idx = findVehicleIndex(list, vehicleSpawn)
    if idx then
        for k, val in pairs(props) do list[idx][k] = val end
        return list[idx]
    else
        local entry = {
            spawncode = upcase(vehicleSpawn),
            owner     = props.owner or false,
            allowed   = props.allowed or false
        }
        table.insert(list, entry)
        return entry
    end
end

-- Remove ALL occurrences of a vehicle across ALL identifiers
local function removeVehicleEverywhere(cfg, vehicleSpawn)
    local want = upcase(vehicleSpawn)
    for identifier, list in pairs(cfg) do
        for i = #list, 1, -1 do
            if upcase(list[i].spawncode) == want then
                table.remove(list, i)
            end
        end
        if #list == 0 then
            cfg[identifier] = nil -- optional: prune empty buckets
        end
    end
end

-- Check if src is the owner of a given vehicle
local function playerOwnsVehicle(cfg, src, vehicleSpawn)
    local id = primaryId(src)
    if not id then return false end
    local list = cfg[id]
    if not list then return false end
    local idx = findVehicleIndex(list, vehicleSpawn)
    if not idx then return false end
    return list[idx].owner == true
end

-- Validate a target player id (server id)
local function validPlayerId(serverId)
    if type(serverId) ~= "number" then return false end
    local ids = GetPlayerIdentifiers(serverId)
    return ids ~= nil and ids[1] ~= nil
end

-- Simple chat helper
local function msg(src, text)
    TriggerClientEvent('chatMessage', src, text)
end

---------------------------------------------------------------------
-- Events: Identifier sync & Client run
---------------------------------------------------------------------

-- Client asks for its identifiers to be sent back
RegisterServerEvent("primerp_vehwl:reloadwl")
AddEventHandler("primerp_vehwl:reloadwl", function()
    local _source = source
    local ids = GetPlayerIdentifiers(_source)
    if ids and #ids > 0 then
        TriggerClientEvent("primerp_vehwl:loadIdentifiers", _source, ids)
    end
end)

-- Server-side join hook to push identifiers once the player is in
AddEventHandler("playerJoining", function()
    local _source = source
    local ids = GetPlayerIdentifiers(_source)
    if ids and #ids > 0 then
        TriggerClientEvent("primerp_vehwl:loadIdentifiers", _source, ids)
    end
end)

-- Client asks server to supply current cfg for checks
RegisterNetEvent('primerp_vehwl:Server:Check')
AddEventHandler('primerp_vehwl:Server:Check', function()
    local cfg = readConfig()
    TriggerClientEvent('primerp_vehwl:RunCode:Client', source, cfg)
end)

-- Optional: external save event (kept for compatibility)
RegisterServerEvent("primerp_vehwl:saveFile")
AddEventHandler("primerp_vehwl:saveFile", function(data)
    writeConfig(data or {})
end)

---------------------------------------------------------------------
-- Commands
---------------------------------------------------------------------

-- /vehicles : list allowed vehicles for the caller
RegisterCommand("vehicles", function(source)
    local cfg = readConfig()
    local id = primaryId(source)
    if not id then
        msg(source, prefix .. "^1No identifiers found.")
        return
    end
    local list = cfg[id] or {}
    local allowed = {}
    for _, v in ipairs(list) do
        if v.allowed == true then table.insert(allowed, v.spawncode) end
    end
    if #allowed > 0 then
        msg(source, prefix .. "^2You are allowed to drive:")
        msg(source, "^0" .. table.concat(allowed, ", "))
    else
        msg(source, prefix .. "^1You currently do not have access to any personal vehicles.")
    end
end)

-- /clear <spawncode> : remove all ownership/permissions for that vehicle across everyone
RegisterCommand("clear", function(source, args)
    if not IsPlayerAceAllowed(source, "VehwlCommands.Access") then
        msg(source, prefix .. "^1You do not have permission to use this command.")
        return
    end
    if #args < 1 then
        msg(source, prefix .. "^1ERROR: Usage ^0/clear <spawncode>")
        return
    end
    local vehicle = args[1]
    local cfg = readConfig()
    removeVehicleEverywhere(cfg, vehicle)
    writeConfig(cfg)
    msg(source, prefix .. "^2Success: Removed all data of vehicle ^5" .. upcase(vehicle))
    TriggerClientEvent('vehwl:Cache:Update:ClearVeh', -1, upcase(vehicle)) -- kept for compatibility
end)

-- /setOwner <id> <spawncode> : set a player as the owner (unique owner per vehicle)
RegisterCommand("setOwner", function(source, args)
    if not IsPlayerAceAllowed(source, "VehwlCommands.Access") then
        msg(source, prefix .. "^1You do not have permission to use this command.")
        return
    end
    if #args < 2 then
        msg(source, prefix .. "^1ERROR: Usage ^0/setOwner <id> <spawncode>")
        return
    end

    local target = tonumber(args[1])
    local vehicle = args[2]
    if not validPlayerId(target) then
        msg(source, prefix .. "^1Invalid player ID.")
        return
    end

    local cfg = readConfig()

    -- Enforce single owner globally
    local existingOwner = findOwnerOfVehicle(cfg, vehicle)
    if existingOwner then
        msg(source, prefix .. "^1That vehicle already has an owner. Use ^0/clear " .. upcase(vehicle) .. " ^1first.")
        return
    end

    local targetId = primaryId(target)
    local list = ensureList(cfg, targetId)
    upsertVehicle(list, vehicle, { owner = true, allowed = true })
    writeConfig(cfg)

    msg(source, prefix .. "^2Set ^5" .. GetPlayerName(target) .. "^2 as owner of ^5" .. upcase(vehicle))
    msg(target, prefix .. "^2You are now the owner of ^5" .. upcase(vehicle) .. "^2 (set by ^5" .. GetPlayerName(source) .. "^2)")
end)

-- Shared trust/untrust implementation
local function setTrustInternal(ownerSrc, targetServerId, vehicle, makeAllowed)
    local cfg = readConfig()

    -- Only the *current owner* of the vehicle can modify trust
    if not playerOwnsVehicle(cfg, ownerSrc, vehicle) then
        msg(ownerSrc, prefix .. "^1ERROR: You do not own this vehicle.")
        return
    end

    if ownerSrc == targetServerId then
        local word = makeAllowed and "trust" or "untrust"
        msg(ownerSrc, prefix .. "^1ERROR: You cannot " .. word .. " yourself.")
        return
    end

    if not validPlayerId(targetServerId) then
        msg(ownerSrc, prefix .. "^1That is not a valid player ID.")
        return
    end

    local targetId = primaryId(targetServerId)
    local list = ensureList(cfg, targetId)
    upsertVehicle(list, vehicle, { owner = false, allowed = makeAllowed })
    writeConfig(cfg)

    if makeAllowed then
        msg(ownerSrc, prefix .. "^2Success: You have given ^5" .. GetPlayerName(targetServerId) ..
            "^2 permission to drive your ^5" .. upcase(vehicle))
        msg(targetServerId, prefix .. "^2You were trusted to use ^5" .. upcase(vehicle) ..
            "^2 by owner ^5" .. GetPlayerName(ownerSrc))
    else
        msg(ownerSrc, prefix .. "^2Success: ^1Player ^5" .. GetPlayerName(targetServerId) ..
            "^1 no longer has permission to drive your ^5" .. upcase(vehicle))
        msg(targetServerId, prefix .. "^1Your permission to use ^5" .. upcase(vehicle) ..
            " ^1was revoked by owner ^5" .. GetPlayerName(ownerSrc))
    end
end

-- /trust <id> <spawncode>
RegisterCommand("trust", function(source, args)
    if #args < 2 then
        msg(source, prefix .. "^1ERROR: Usage ^0/trust <id> <spawncode>")
        return
    end
    local target = tonumber(args[1])
    local vehicle = args[2]
    setTrustInternal(source, target, vehicle, true)
end)

-- /untrust <id> <spawncode>
RegisterCommand("untrust", function(source, args)
    if #args < 2 then
        msg(source, prefix .. "^1ERROR: Usage ^0/untrust <id> <spawncode>")
        return
    end
    local target = tonumber(args[1])
    local vehicle = args[2]
    setTrustInternal(source, target, vehicle, false)
end)
