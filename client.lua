local identifiers = {}

-- Show notification
function ShowInfo(text)
    SetNotificationTextEntry("STRING")
    AddTextComponentSubstringPlayerName(text)
    DrawNotification(false, false)
end

-- Load identifiers and periodically check whitelist
Citizen.CreateThread(function()
    local myIds = getIdentifiers() -- ✅ renamed "myIdss" to "myIds" for consistency
    print(json.encode(myIds))      -- ✅ safer print since it's a table
    while true do
        Citizen.Wait(10000)
        TriggerServerEvent("primerp_vehwl:reloadwl")
        TriggerServerEvent("primerp_vehwl:Server:Check")
    end
end)

-- Load whitelist config
function getConfig()
    return LoadResourceFile(GetCurrentResourceName(), "whitelist.json")
end

-- Reload whitelist on spawn
AddEventHandler("playerSpawned", function()
    TriggerServerEvent("primerp_vehwl:reloadwl")
end)

-- Return identifiers
function getIdentifiers()
    return identifiers
end

-- Main check
RegisterNetEvent("primerp_vehwl:RunCode:Client")
AddEventHandler("primerp_vehwl:RunCode:Client", function(cfg)
    local ped = PlayerPedId()              -- ✅ GetPlayerPed(-1) is deprecated
    local inVeh = IsPedInAnyVehicle(ped, false)
    local veh = GetVehiclePedIsUsing(ped)
    local driver = GetPedInVehicleSeat(veh, -1)
    local spawncode = GetEntityModel(veh)
    local allowed, exists = false, false
    local myIds = getIdentifiers()

    if inVeh and driver == ped then
        for pair, vehicles in pairs(cfg) do
            -- Check if vehicle exists in config
            for _, vehic in ipairs(vehicles) do
                if GetHashKey(vehic.spawncode) == spawncode then
                    exists = true
                end
            end

            -- Check if current identifier matches and is allowed
            if pair == myIds[1] then
                for _, v in ipairs(vehicles) do
                    if spawncode == GetHashKey(v.spawncode) and v.allowed then
                        allowed = true
                        print("Allowed was set to true with vehicle == " .. v.spawncode)
                    end
                end
            end
        end
    end

    if exists and not allowed then
        DeleteEntity(veh)
        ClearPedTasksImmediately(ped)
        TriggerEvent("primerp_vehwl:RunCode:Success") -- ✅ removed "source" (not available on client)
    end
end)

-- Notify player when access denied
RegisterNetEvent("primerp_vehwl:RunCode:Success")
AddEventHandler("primerp_vehwl:RunCode:Success", function()
    ShowInfo("~r~ERROR: You do not have access to this personal vehicle")
end)

-- Load identifiers from server
RegisterNetEvent("primerp_vehwl:loadIdentifiers")
AddEventHandler("primerp_vehwl:loadIdentifiers", function(id)
    identifiers = id
end)

-- Manual reload command
RegisterCommand("reloadwl", function()
    TriggerServerEvent("primerp_vehwl:reloadwl")
end)

--[[
    Commands:
        /setOwner <id> <spawncode>
        /trust <id> <spawncode>
        /untrust <id> <spawncode>
        /vehicle list
--]]
