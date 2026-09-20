local REQUIRE_ACE = GetConvar('sd_vmenu_require_ace', 'false') == 'true'

local ACTION_PERMS = {
  spawn_saved_vehicle = 'vMenu.SavedVehicles.Spawn',
  spawn_saved_ped = 'vMenu.PlayerAppearance.SpawnSaved',
  spawn_saved_mp_ped = 'vMenu.PlayerAppearance.SpawnSaved',
  vehicle_extra = 'vMenu.VehicleOptions.Extras',
  teleport_option = 'vMenu.MiscSettings.TeleportLocations'
}



local VMENU_RESOURCE_NAME = GetConvar('sd_vmenu_resource_name', 'vMenu')
local cachedTeleportLocations = nil
local cachedTeleportLocationsAt = 0

local function normalizeTeleportLocation(loc, index)
  if type(loc) ~= 'table' then return nil end
  local name = tostring(loc.name or loc.Name or loc.label or loc.Label or ('Location ' .. tostring(index)))
  local coords = loc.coordinates or loc.Coordinates or loc.coords or loc.Coords or loc.position or loc.Position
  local x = loc.x or loc.X
  local y = loc.y or loc.Y
  local z = loc.z or loc.Z
  if type(coords) == 'table' then
    x = x or coords.x or coords.X or coords[1]
    y = y or coords.y or coords.Y or coords[2]
    z = z or coords.z or coords.Z or coords[3]
  end
  if not x or not y or not z then return nil end
  local h = loc.heading or loc.Heading or loc.h or loc.H or 0.0
  return {
    id = tostring(name),
    name = name,
    x = tonumber(x) or 0.0,
    y = tonumber(y) or 0.0,
    z = tonumber(z) or 0.0,
    h = tonumber(h) or 0.0,
    source = 'vMenu locations.json'
  }
end

local function getVMenuTeleportLocations(force)
  local now = GetGameTimer and GetGameTimer() or os.time()
  if not force and cachedTeleportLocations and (now - cachedTeleportLocationsAt) < 30000 then
    return cachedTeleportLocations
  end

  local out = {}
  local raw = LoadResourceFile(VMENU_RESOURCE_NAME, 'config/locations.json') or LoadResourceFile(VMENU_RESOURCE_NAME, 'locations.json')
  if raw and raw ~= '' then
    local ok, decoded = pcall(json.decode, raw)
    if ok and type(decoded) == 'table' then
      local list = decoded.teleports or decoded.Teleports or decoded.locations or decoded.Locations or decoded
      if type(list) == 'table' then
        for i, loc in ipairs(list) do
          local item = normalizeTeleportLocation(loc, i)
          if item then out[#out + 1] = item end
        end
      end
    else
      print(('[sd_vmenu] Could not parse %s config/locations.json'):format(VMENU_RESOURCE_NAME))
    end
  else
    print(('[sd_vmenu] Could not read %s/config/locations.json. Set sd_vmenu_resource_name if your vMenu resource folder has a different name.'):format(VMENU_RESOURCE_NAME))
  end

  table.sort(out, function(a,b) return a.name:lower() < b.name:lower() end)
  cachedTeleportLocations = out
  cachedTeleportLocationsAt = now
  return out
end

RegisterNetEvent('sd_vmenu:requestInfo', function()
  local src = source
  TriggerClientEvent('sd_vmenu:setTeleportOptions', src, getVMenuTeleportLocations(false))
end)

RegisterNetEvent('sd_vmenu:requestAction', function(action, args)
  local src = source
  action = tostring(action or '')
  args = type(args) == 'table' and args or {}

  if REQUIRE_ACE then
    local ace = ACTION_PERMS[action]
    if ace and not IsPlayerAceAllowed(src, ace) then
      TriggerClientEvent('sd_vmenu:notify', src, ('~r~Stream Deck denied: missing ACE %s'):format(ace))
      return
    end
  end

  TriggerClientEvent('sd_vmenu:runAction', src, action, args)
end)
