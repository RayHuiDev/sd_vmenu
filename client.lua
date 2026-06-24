local registered = false
local serverTeleports = {}

local function notify(msg)
  BeginTextCommandThefeedPost('STRING')
  AddTextComponentSubstringPlayerName(msg)
  EndTextCommandThefeedPostTicker(false, false)
end
RegisterNetEvent('sd_vmenu:notify', notify)
RegisterNetEvent('sd_vmenu:setTeleportOptions', function(list) serverTeleports = type(list) == 'table' and list or {} end)

local function currentVehicleExtras()
  -- Keep this list static on purpose. Users change vehicles often, so the
  -- Stream Deck dropdown should always offer the same Extra 1-12 choices.
  local extras = {}
  for i = 1, 12 do
    extras[#extras + 1] = { id = i, name = 'Extra ' .. i }
  end
  return extras
end

local function teleportOptions()
  return type(serverTeleports) == 'table' and serverTeleports or {}
end

local function announceToStreamDeck()
  TriggerServerEvent('sd_vmenu:requestInfo')
  SendNUIMessage({
    type = 'register',
    resource = GetCurrentResourceName(),
    playerServerId = GetPlayerServerId(PlayerId()),
    playerName = GetPlayerName(PlayerId()) or 'FiveM Player',
    vehicleExtras = currentVehicleExtras(),
    teleports = teleportOptions()
  })
end

CreateThread(function()
  Wait(2500)
  while true do announceToStreamDeck(); Wait(5000) end
end)

RegisterNUICallback('sdConnected', function(data, cb)
  if not registered then registered = true; notify('~g~Stream Deck connected to FiveM.') end
  cb({ ok = true })
end)

RegisterNUICallback('sdAction', function(data, cb)
  local action = tostring(data.action or '')
  local args = data.args or {}
  if action == '' then cb({ ok = false, error = 'missing action' }); return end
  TriggerServerEvent('sd_vmenu:requestAction', action, args)
  cb({ ok = true })
end)

local function requestModel(model)
  if not model or model == '' then return nil end
  local hash = type(model) == 'number' and model or joaat(tostring(model))
  RequestModel(hash)
  local deadline = GetGameTimer() + 5000
  while not HasModelLoaded(hash) and GetGameTimer() < deadline do Wait(0) end
  if not HasModelLoaded(hash) then return nil end
  return hash
end

local function applySavedVehicleData(veh, raw)
  if type(raw) ~= 'table' then return end
  if raw.plateText then SetVehicleNumberPlateText(veh, tostring(raw.plateText):sub(1, 8)) end
  if raw.plateStyle then SetVehicleNumberPlateTextIndex(veh, tonumber(raw.plateStyle) or 0) end
  if raw.windowTint then SetVehicleWindowTint(veh, tonumber(raw.windowTint) or 0) end
  if raw.livery then SetVehicleLivery(veh, tonumber(raw.livery) or 0) end
  if raw.wheelType then SetVehicleWheelType(veh, tonumber(raw.wheelType) or 0) end
  if type(raw.colors) == 'table' then
    local p = raw.colors.primary or raw.colors.primaryColor or raw.colors[1]
    local se = raw.colors.secondary or raw.colors.secondaryColor or raw.colors[2]
    if p and se then SetVehicleColours(veh, tonumber(p) or 0, tonumber(se) or 0) end
  elseif raw.primaryColor and raw.secondaryColor then
    SetVehicleColours(veh, tonumber(raw.primaryColor) or 0, tonumber(raw.secondaryColor) or 0)
  end
  if type(raw.extras) == 'table' then for k,v in pairs(raw.extras) do SetVehicleExtra(veh, tonumber(k) or k, (v == false or v == 0) and 1 or 0) end end
  if type(raw.mods) == 'table' then SetVehicleModKit(veh, 0); for k,v in pairs(raw.mods) do SetVehicleMod(veh, tonumber(k) or k, tonumber(v) or -1, false) end end
end

local function spawnSavedVehicle(args)
  local raw = type(args) == 'table' and args.savedVehicleData or nil
  if type(raw) ~= 'table' then return notify('~r~No saved vehicle selected in Stream Deck.') end
  local model = raw.model or raw.modelName or raw.spawnName or raw.vehicle
  local hash = raw.modelHash or raw.vehicleHash or raw.hash
  if type(model) == 'table' then hash = hash or model.modelHash; model = model.model or model.modelName or model.spawnName end
  if type(model) == 'number' then hash = model; model = nil end
  local vehicleHash = requestModel(model or hash)
  if not vehicleHash then return notify('~r~Could not load saved vehicle model.') end
  local ped = PlayerPedId(); local coords = GetEntityCoords(ped); local heading = GetEntityHeading(ped)
  local veh = CreateVehicle(vehicleHash, coords.x, coords.y, coords.z, heading, true, false)
  SetEntityAsMissionEntity(veh, true, true); SetVehicleOnGroundProperly(veh); SetPedIntoVehicle(ped, veh, -1)
  applySavedVehicleData(veh, raw); SetModelAsNoLongerNeeded(vehicleHash)
  notify('~g~Spawned saved vehicle: ' .. tostring(args.savedVehicleName or raw.name or 'Saved Vehicle'))
end

local function getTableValue(t, key, default)
  if type(t) ~= 'table' then return default end
  local v = t[key]
  if v == nil then v = t[tostring(key)] end
  if v == nil then return default end
  return v
end

local function toNumber(v, default)
  local n = tonumber(v)
  if n == nil then return default end
  return n
end

local function preservePedState(oldPed)
  local state = {
    coords = GetEntityCoords(oldPed),
    heading = GetEntityHeading(oldPed),
    health = GetEntityHealth(oldPed),
    maxHealth = GetEntityMaxHealth(oldPed),
    armor = GetPedArmour(oldPed),
    vehicle = 0,
    seat = nil
  }
  if IsPedInAnyVehicle(oldPed, false) then
    local veh = GetVehiclePedIsIn(oldPed, false)
    state.vehicle = veh
    local maxPassengers = GetVehicleMaxNumberOfPassengers(veh) or 0
    for seat = -1, maxPassengers do
      if GetPedInVehicleSeat(veh, seat) == oldPed then state.seat = seat; break end
    end
  end
  return state
end

local function restorePedState(ped, state)
  if not ped or ped == 0 or type(state) ~= 'table' then return end
  if state.maxHealth and state.maxHealth > 0 then SetEntityMaxHealth(ped, state.maxHealth) end
  if state.health and state.health > 0 then SetEntityHealth(ped, state.health) end
  if state.armor then SetPedArmour(ped, state.armor) end
  if state.coords then SetEntityCoordsNoOffset(ped, state.coords.x, state.coords.y, state.coords.z, false, false, false) end
  if state.heading then SetEntityHeading(ped, state.heading) end
  if state.vehicle and state.vehicle ~= 0 and DoesEntityExist(state.vehicle) and state.seat ~= nil then
    TaskWarpPedIntoVehicle(ped, state.vehicle, state.seat)
  end
end

local function forcePedVisible(ped)
  if not ped or ped == 0 then return end
  FreezeEntityPosition(ped, false)
  SetEntityCollision(ped, true, true)
  SetEntityVisible(ped, true, false)
  ResetEntityAlpha(ped)
  SetPedCanRagdoll(ped, true)
end

local function switchPlayerModel(hash)
  if not hash then return nil end
  if not IsModelInCdimage(hash) then return nil end
  if not requestModel(hash) then return nil end

  local oldPed = PlayerPedId()
  local state = preservePedState(oldPed)
  SetPlayerModel(PlayerId(), hash)

  local deadline = GetGameTimer() + 2500
  local ped = PlayerPedId()
  while GetGameTimer() < deadline do
    ped = PlayerPedId()
    if ped ~= 0 and GetEntityModel(ped) == hash then break end
    Wait(0)
  end

  ped = PlayerPedId()
  restorePedState(ped, state)
  forcePedVisible(ped)
  SetModelAsNoLongerNeeded(hash)
  return ped
end

local function applyRegularPedAppearance(ped, raw)
  if not ped or ped == 0 or type(raw) ~= 'table' then return end
  SetPedDefaultComponentVariation(ped)
  ClearAllPedProps(ped)
  ClearPedDecorations(ped)
  ClearPedFacialDecorations(ped)

  local version = toNumber(raw.version or raw.Version, -1)
  if version ~= 1 then return end

  local drawables = raw.drawableVariations or raw.DrawableVariations or {}
  local textures = raw.drawableVariationTextures or raw.DrawableVariationTextures or {}
  for component = 0, 11 do
    local drawable = getTableValue(drawables, component, nil)
    local texture = getTableValue(textures, component, 0)
    if drawable ~= nil then
      SetPedComponentVariation(ped, component, toNumber(drawable, 0), toNumber(texture, 0), 0)
    end
  end

  local props = raw.props or raw.Props or {}
  local propTextures = raw.propTextures or raw.PropTextures or {}
  for prop = 0, 7 do
    local propIndex = getTableValue(props, prop, -1)
    local propTexture = getTableValue(propTextures, prop, 0)
    if toNumber(propIndex, -1) < 0 then
      ClearPedProp(ped, prop)
    else
      SetPedPropIndex(ped, prop, toNumber(propIndex, 0), toNumber(propTexture, 0), true)
    end
  end
end

local function kvpPairValue(pair, field, default)
  if type(pair) ~= 'table' then return default end
  local v = pair[field]
  if v == nil and field == 'Key' then v = pair.key end
  if v == nil and field == 'Value' then v = pair.value end
  if v == nil then return default end
  return v
end

local function applyMpPedAppearance(ped, raw)
  if not ped or ped == 0 or type(raw) ~= 'table' then return end
  ClearPedDecorations(ped)
  ClearPedFacialDecorations(ped)
  SetPedDefaultComponentVariation(ped)
  SetPedHairColor(ped, 0, 0)
  SetPedEyeColor(ped, 0)
  ClearAllPedProps(ped)

  local hb = raw.PedHeadBlendData or raw.pedHeadBlendData
  if type(hb) == 'table' then
    SetPedHeadBlendData(
      ped,
      toNumber(hb.FirstFaceShape or hb.firstFaceShape, 0),
      toNumber(hb.SecondFaceShape or hb.secondFaceShape, 0),
      toNumber(hb.ThirdFaceShape or hb.thirdFaceShape, 0),
      toNumber(hb.FirstSkinTone or hb.firstSkinTone, 0),
      toNumber(hb.SecondSkinTone or hb.secondSkinTone, 0),
      toNumber(hb.ThirdSkinTone or hb.thirdSkinTone, 0),
      toNumber(hb.ParentFaceShapePercent or hb.parentFaceShapePercent, 0.5),
      toNumber(hb.ParentSkinTonePercent or hb.parentSkinTonePercent, 0.5),
      0.0,
      hb.IsParentInheritance == true or hb.isParentInheritance == true
    )
    local deadline = GetGameTimer() + 2000
    while not HasPedHeadBlendFinished(ped) and GetGameTimer() < deadline do Wait(0) end
  end

  local app = raw.PedAppearance or raw.pedAppearance
  if type(app) == 'table' then
    SetPedComponentVariation(ped, 2, toNumber(app.hairStyle, 0), 0, 0)
    SetPedHairColor(ped, toNumber(app.hairColor, 0), toNumber(app.hairHighlightColor, 0))
    if type(app.HairOverlay) == 'table' and app.HairOverlay.Key and app.HairOverlay.Value and app.HairOverlay.Key ~= '' and app.HairOverlay.Value ~= '' then
      SetPedFacialDecoration(ped, joaat(app.HairOverlay.Key), joaat(app.HairOverlay.Value))
    end
    SetPedHeadOverlay(ped, 0, toNumber(app.blemishesStyle, 0), toNumber(app.blemishesOpacity, 0.0))
    SetPedHeadOverlay(ped, 1, toNumber(app.beardStyle, 0), toNumber(app.beardOpacity, 0.0)); SetPedHeadOverlayColor(ped, 1, 1, toNumber(app.beardColor, 0), toNumber(app.beardColor, 0))
    SetPedHeadOverlay(ped, 2, toNumber(app.eyebrowsStyle, 0), toNumber(app.eyebrowsOpacity, 0.0)); SetPedHeadOverlayColor(ped, 2, 1, toNumber(app.eyebrowsColor, 0), toNumber(app.eyebrowsColor, 0))
    SetPedHeadOverlay(ped, 3, toNumber(app.ageingStyle, 0), toNumber(app.ageingOpacity, 0.0))
    SetPedHeadOverlay(ped, 4, toNumber(app.makeupStyle, 0), toNumber(app.makeupOpacity, 0.0)); SetPedHeadOverlayColor(ped, 4, 2, toNumber(app.makeupColor, 0), toNumber(app.makeupColor, 0))
    SetPedHeadOverlay(ped, 5, toNumber(app.blushStyle, 0), toNumber(app.blushOpacity, 0.0)); SetPedHeadOverlayColor(ped, 5, 2, toNumber(app.blushColor, 0), toNumber(app.blushColor, 0))
    SetPedHeadOverlay(ped, 6, toNumber(app.complexionStyle, 0), toNumber(app.complexionOpacity, 0.0))
    SetPedHeadOverlay(ped, 7, toNumber(app.sunDamageStyle, 0), toNumber(app.sunDamageOpacity, 0.0))
    SetPedHeadOverlay(ped, 8, toNumber(app.lipstickStyle, 0), toNumber(app.lipstickOpacity, 0.0)); SetPedHeadOverlayColor(ped, 8, 2, toNumber(app.lipstickColor, 0), toNumber(app.lipstickColor, 0))
    SetPedHeadOverlay(ped, 9, toNumber(app.molesFrecklesStyle, 0), toNumber(app.molesFrecklesOpacity, 0.0))
    SetPedHeadOverlay(ped, 10, toNumber(app.chestHairStyle, 0), toNumber(app.chestHairOpacity, 0.0)); SetPedHeadOverlayColor(ped, 10, 1, toNumber(app.chestHairColor, 0), toNumber(app.chestHairColor, 0))
    SetPedHeadOverlay(ped, 11, toNumber(app.bodyBlemishesStyle, 0), toNumber(app.bodyBlemishesOpacity, 0.0))
    SetPedEyeColor(ped, toNumber(app.eyeColor, 0))
  end

  local face = raw.FaceShapeFeatures or raw.faceShapeFeatures
  for i = 0, 19 do SetPedFaceFeature(ped, i, 0.0) end
  if type(face) == 'table' and type(face.features) == 'table' then
    for k, v in pairs(face.features) do SetPedFaceFeature(ped, toNumber(k, 0), toNumber(v, 0.0)) end
  end

  local dv = raw.DrawableVariations or raw.drawableVariations
  if type(dv) == 'table' and type(dv.clothes) == 'table' then
    for k, pair in pairs(dv.clothes) do
      SetPedComponentVariation(ped, toNumber(k, 0), toNumber(kvpPairValue(pair, 'Key', 0), 0), toNumber(kvpPairValue(pair, 'Value', 0), 0), 0)
    end
  end

  local pv = raw.PropVariations or raw.propVariations
  if type(pv) == 'table' and type(pv.props) == 'table' then
    for k, pair in pairs(pv.props) do
      local prop = toNumber(kvpPairValue(pair, 'Key', -1), -1)
      local texture = toNumber(kvpPairValue(pair, 'Value', 0), 0)
      local propSlot = toNumber(k, 0)
      if prop < 0 then ClearPedProp(ped, propSlot) else SetPedPropIndex(ped, propSlot, prop, texture, true) end
    end
  end

  local tattoos = raw.PedTatttoos or raw.PedTattoos or raw.pedTatttoos or raw.pedTattoos
  if type(tattoos) == 'table' then
    local groups = { 'HairTattoos', 'HeadTattoos', 'TorsoTattoos', 'LeftArmTattoos', 'RightArmTattoos', 'LeftLegTattoos', 'RightLegTattoos', 'BadgeTattoos', 'AddonTattoos' }
    for _, group in ipairs(groups) do
      if type(tattoos[group]) == 'table' then
        for collection, overlay in pairs(tattoos[group]) do
          if collection and overlay and collection ~= '' and overlay ~= '' then AddPedDecorationFromHashes(ped, joaat(collection), joaat(overlay)) end
        end
      end
    end
  end

  if raw.FacialExpression and raw.FacialExpression ~= '' then
    SetFacialIdleAnimOverride(ped, raw.FacialExpression, '')
  end
end

local function spawnRegularPed(args)
  local raw = type(args) == 'table' and args.savedPedData or nil
  if type(raw) ~= 'table' then return notify('~r~No saved ped selected in Stream Deck.') end
  local model = raw.model or raw.Model or raw.modelHash or raw.ModelHash or raw.ModelName or raw.modelName or raw.PedModel or raw.pedModel
  local hash = requestModel(model)
  if not hash then return notify('~r~Could not load saved ped model.') end
  local ped = switchPlayerModel(hash)
  if not ped then return notify('~r~Could not switch to saved ped model.') end
  Wait(100)
  ped = PlayerPedId()
  applyRegularPedAppearance(ped, raw)
  forcePedVisible(ped)
  notify('~g~Spawned saved ped: ' .. tostring(args.savedPedName or raw.name or 'Saved Ped'))
end

local function spawnMpPed(args)
  local raw = type(args) == 'table' and args.savedMpPedData or nil
  if type(raw) ~= 'table' then return notify('~r~No saved MP ped selected in Stream Deck.') end
  local modelHash = raw.ModelHash or raw.modelHash
  if not modelHash then
    if raw.IsMale == false or raw.isMale == false then modelHash = joaat('mp_f_freemode_01') else modelHash = joaat('mp_m_freemode_01') end
  end
  local hash = requestModel(modelHash)
  if not hash then return notify('~r~Could not load MP ped model.') end
  local ped = switchPlayerModel(hash)
  if not ped then return notify('~r~Could not switch to MP ped model.') end
  Wait(100)
  ped = PlayerPedId()
  applyMpPedAppearance(ped, raw)
  forcePedVisible(ped)
  notify('~g~Spawned saved MP ped: ' .. tostring(args.savedMpPedName or raw.SaveName or 'Saved MP Ped'))
end

local function setVehicleExtra(args)
  local veh = GetVehiclePedIsIn(PlayerPedId(), false)
  if veh == 0 then return notify('~r~You are not in a vehicle.') end

  local extra = tonumber(args.extra)
  if not extra or extra < 1 or extra > 12 then
    return notify('~r~Select an extra from 1-12 in Stream Deck.')
  end

  if not DoesExtraExist(veh, extra) then
    return notify(('~y~Extra %s is not available on this vehicle.'):format(extra))
  end

  local mode = tostring(args.mode or 'toggle')
  local disable
  if mode == 'on' then
    disable = 0
  elseif mode == 'off' then
    disable = 1
  else
    disable = IsVehicleExtraTurnedOn(veh, extra) and 1 or 0
  end

  SetVehicleExtra(veh, extra, disable)
  notify(('~g~Vehicle extra %s %s.'):format(extra, IsVehicleExtraTurnedOn(veh, extra) and 'on' or 'off'))
end

local function teleportOption(args)
  local id = tostring(args.teleportId or '')
  if id == '' then return notify('~r~No teleport option selected in Stream Deck.') end
  for _, t in ipairs(teleportOptions()) do
    if tostring(t.id) == id then
      local ped = PlayerPedId(); local ent = IsPedInAnyVehicle(ped, false) and GetVehiclePedIsIn(ped, false) or ped
      SetEntityCoordsNoOffset(ent, tonumber(t.x)+0.0, tonumber(t.y)+0.0, tonumber(t.z)+0.0, false, false, false)
      SetEntityHeading(ent, tonumber(t.h) or 0.0)
      notify('~g~Teleported to: ' .. tostring(t.name))
      return
    end
  end
  notify('~r~Teleport option not found in vMenu locations.')
end

RegisterNetEvent('sd_vmenu:runAction', function(action, args)
  args = type(args) == 'table' and args or {}
  if action == 'spawn_saved_vehicle' then spawnSavedVehicle(args)
  elseif action == 'spawn_saved_ped' then spawnRegularPed(args)
  elseif action == 'spawn_saved_mp_ped' then spawnMpPed(args)
  elseif action == 'vehicle_extra' then setVehicleExtra(args)
  elseif action == 'teleport_option' then teleportOption(args)
  else notify('~r~Unknown Stream Deck action: ' .. tostring(action)) end
end)
