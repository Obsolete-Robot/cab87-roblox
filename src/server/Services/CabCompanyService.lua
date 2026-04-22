local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local CabCompanyService = {}
CabCompanyService.__index = CabCompanyService

local REQUEST_PROMPT_ATTRIBUTE = "Cab87CabRequestPrompt"
local REQUEST_ACTION_ATTRIBUTE = "Cab87CabRequestAction"
local REQUEST_ZONE_ATTRIBUTE = "Cab87CabRequestZone"

local ACTION_ZONES = {
	claim = { "CabPickupZone" },
	recover = { "CabPickupZone", "GarageZone", "ServiceDeskZone" },
	shop = { "GarageZone", "ServiceDeskZone" },
}

local PROMPT_DEFINITIONS = {
	{
		zoneName = "CabPickupZone",
		action = "claim",
		actionText = "Claim Cab",
	},
	{
		zoneName = "GarageZone",
		action = "recover",
		actionText = "Recover Cab",
	},
	{
		zoneName = "GarageZone",
		action = "shop",
		actionText = "Open Garage",
	},
	{
		zoneName = "ServiceDeskZone",
		action = "recover",
		actionText = "Recover Cab",
	},
	{
		zoneName = "ServiceDeskZone",
		action = "shop",
		actionText = "Open Garage",
	},
}

local function getConfigNumber(config, key, fallback)
	local value = config and config[key]
	if type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge then
		return value
	end

	return fallback
end

local function getConfigString(config, key, fallback)
	local value = config and config[key]
	if type(value) == "string" and value ~= "" then
		return value
	end

	return fallback
end

local function sanitizeString(value)
	if type(value) == "string" and value ~= "" then
		return value
	end

	return nil
end

local function promptNameForAction(action)
	local normalized = string.lower(tostring(action or "claim"))
	return "RequestCabPrompt_" .. normalized
end

local function normalizeAction(action)
	action = string.lower(tostring(action or "claim"))
	if action == "reset" or action == "recover" then
		return "recover"
	end
	if action == "shop" then
		return "shop"
	end
	if action == "claim" then
		return "claim"
	end

	return "claim"
end

local function getOwnerUserId(player)
	if typeof(player) == "Instance" and player:IsA("Player") then
		return player.UserId
	end

	return nil
end

local function getPlayerRootPart(player)
	local character = player and player.Character
	if not character then
		return nil
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if rootPart and rootPart:IsA("BasePart") then
		return rootPart
	end

	local primaryPart = character.PrimaryPart
	if primaryPart and primaryPart:IsA("BasePart") then
		return primaryPart
	end

	return nil
end

local function horizontalDistance(a, b)
	local dx = a.X - b.X
	local dz = a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

local function yawFromCFrame(cframe)
	local look = cframe.LookVector
	local horizontal = Vector3.new(look.X, 0, look.Z)
	if horizontal.Magnitude <= 0.001 then
		return 0
	end

	local unit = horizontal.Unit
	return math.atan2(unit.X, unit.Z)
end

local function isPointInZone(zone, position, padding)
	local localPosition = zone.CFrame:PointToObjectSpace(position)
	local halfSize = zone.Size * 0.5
	local verticalPadding = math.max(padding, 12)

	return math.abs(localPosition.X) <= halfSize.X + padding
		and math.abs(localPosition.Z) <= halfSize.Z + padding
		and math.abs(localPosition.Y) <= halfSize.Y + verticalPadding
end

local function getPayload(actionOrPayload, taxiId)
	if type(actionOrPayload) == "table" then
		return {
			action = actionOrPayload.action,
			taxiId = actionOrPayload.taxiId,
			zoneName = actionOrPayload.zoneName,
		}
	end

	return {
		action = actionOrPayload,
		taxiId = taxiId,
	}
end

function CabCompanyService.new(options)
	options = options or {}

	return setmetatable({
		config = options.config or {},
		remotes = options.remotes or {},
		world = options.world,
		taxiService = options.taxiService,
		vehicleCatalog = options.vehicleCatalog,
		vehicleInventoryService = options.vehicleInventoryService,
		onCabReady = options.onCabReady,
		connections = {},
		lastRequestAtByUserId = {},
		started = false,
	}, CabCompanyService)
end

function CabCompanyService:_trackConnection(connection)
	table.insert(self.connections, connection)
	return connection
end

function CabCompanyService:_getCabCompanyRoot()
	local world = self.world
	if not world then
		return nil
	end

	local root = world:FindFirstChild("CabCompany")
	if root and root:IsA("Folder") then
		return root
	end

	return nil
end

function CabCompanyService:_getZonesFolder()
	local root = self:_getCabCompanyRoot()
	local zonesFolder = root and root:FindFirstChild("ServiceZones")
	if zonesFolder and zonesFolder:IsA("Folder") then
		return zonesFolder
	end

	return nil
end

function CabCompanyService:_findZone(zoneName)
	local zonesFolder = self:_getZonesFolder()
	local zone = zonesFolder and zonesFolder:FindFirstChild(zoneName)
	if zone and zone:IsA("BasePart") then
		return zone
	end

	return nil
end

function CabCompanyService:_getSpawnPose()
	local root = self:_getCabCompanyRoot()
	local spawnFolder = root and root:FindFirstChild("Spawn")
	local spawnPoint = spawnFolder and spawnFolder:FindFirstChild("CabSpawnPoint")
	if spawnPoint and spawnPoint:IsA("BasePart") then
		return {
			position = spawnPoint.Position + Vector3.new(0, 1.5, 0),
			yaw = yawFromCFrame(spawnPoint.CFrame),
		}
	end

	local world = self.world
	local spawnX = world and world:GetAttribute("CabCompanySpawnX")
	local spawnY = world and world:GetAttribute("CabCompanySpawnY")
	local spawnZ = world and world:GetAttribute("CabCompanySpawnZ")
	if type(spawnX) == "number" and type(spawnY) == "number" and type(spawnZ) == "number" then
		return {
			position = Vector3.new(spawnX, spawnY, spawnZ),
			yaw = if type(world:GetAttribute("CabCompanySpawnYaw")) == "number"
				then world:GetAttribute("CabCompanySpawnYaw")
				else 0,
		}
	end

	return {
		position = self.config.carSpawn,
		yaw = 0,
	}
end

function CabCompanyService:_isKnownTaxiId(taxiId)
	if not sanitizeString(taxiId) then
		return false
	end

	if self.vehicleCatalog and self.vehicleCatalog.isKnownTaxiId then
		return self.vehicleCatalog.isKnownTaxiId(taxiId)
	end

	if taxiId == self.config.carDefaultTaxiId or taxiId == self.config.carDefaultProfileName then
		return true
	end

	return false
end

function CabCompanyService:_resolveTaxiId(player, requestedTaxiId)
	local selectedAttribute = getConfigString(self.config, "carSelectedTaxiIdAttribute", "Cab87SelectedTaxiId")
	local defaultTaxiId = getConfigString(self.config, "carDefaultTaxiId", nil)
		or (
			self.vehicleCatalog
			and self.vehicleCatalog.getStarterTaxiId
			and self.vehicleCatalog.getStarterTaxiId()
		)
		or getConfigString(self.config, "carDefaultProfileName", "PlayerTaxi")
	local taxiId = sanitizeString(requestedTaxiId)
		or (
			self.vehicleInventoryService
			and self.vehicleInventoryService.getEquippedTaxiId
			and self.vehicleInventoryService:getEquippedTaxiId(player)
		)
		or sanitizeString(player and player:GetAttribute(selectedAttribute))
		or defaultTaxiId

	if self.vehicleInventoryService and not self.vehicleInventoryService:isTaxiOwned(player, taxiId) then
		taxiId = (
			self.vehicleInventoryService
			and self.vehicleInventoryService.getEquippedTaxiId
			and self.vehicleInventoryService:getEquippedTaxiId(player)
		)
			or defaultTaxiId
	end

	if self:_isKnownTaxiId(taxiId) then
		return taxiId
	end

	warn("[cab87] Unknown taxi id requested; falling back to " .. tostring(defaultTaxiId))
	return defaultTaxiId
end

function CabCompanyService:_getValidZoneForAction(action, position)
	local zoneNames = ACTION_ZONES[action] or ACTION_ZONES.claim
	local padding = math.max(getConfigNumber(self.config, "cabCompanyZonePadding", 8), 0)

	for _, zoneName in ipairs(zoneNames) do
		local zone = self:_findZone(zoneName)
		if zone and isPointInZone(zone, position, padding) then
			return zone
		end
	end

	return nil
end

function CabCompanyService:_isInFallbackCompanyRange(position)
	local spawnPose = self:_getSpawnPose()
	local radius = math.max(getConfigNumber(self.config, "cabCompanyFallbackRequestRadius", 95), 0)
	return horizontalDistance(position, spawnPose.position) <= radius
end

function CabCompanyService:_validateRequest(player, action)
	local rootPart = getPlayerRootPart(player)
	if not rootPart then
		return false, "missingCharacter", nil
	end

	local zone = self:_getValidZoneForAction(action, rootPart.Position)
	if zone then
		return true, nil, zone
	end

	local zonesFolder = self:_getZonesFolder()
	if not zonesFolder and self:_isInFallbackCompanyRange(rootPart.Position) then
		return true, nil, nil
	end

	return false, "outOfCabCompanyZone", nil
end

function CabCompanyService:_canRequest(player)
	local ownerUserId = getOwnerUserId(player)
	if not ownerUserId then
		return false
	end

	local cooldown = math.max(getConfigNumber(self.config, "cabCompanyRequestCooldownSeconds", 0.75), 0)
	local now = Workspace:GetServerTimeNow()
	local lastRequestAt = self.lastRequestAtByUserId[ownerUserId]
	if lastRequestAt and now - lastRequestAt < cooldown then
		return false
	end

	self.lastRequestAtByUserId[ownerUserId] = now
	return true
end

function CabCompanyService:_markCabRequest(handle, action, zone)
	local car = handle and handle.car
	if not car then
		return
	end

	car:SetAttribute("Cab87LastCabRequestAction", action)
	car:SetAttribute("Cab87LastCabRequestZone", zone and zone.Name or "")
end

function CabCompanyService:_installPrompt(zoneName, action, actionText)
	local zone = self:_findZone(zoneName)
	if not zone then
		return
	end

	local legacyPrompt = zone:FindFirstChild("RequestCabPrompt")
	if legacyPrompt and legacyPrompt:IsA("ProximityPrompt") then
		legacyPrompt:Destroy()
	elseif legacyPrompt then
		legacyPrompt:Destroy()
	end

	local promptName = promptNameForAction(action)
	local prompt = zone:FindFirstChild(promptName)
	if prompt and not prompt:IsA("ProximityPrompt") then
		prompt:Destroy()
		prompt = nil
	end

	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = promptName
		prompt.Parent = zone
	end

	prompt.ActionText = actionText
	prompt.ObjectText = "Cab Company"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonY
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = math.max(getConfigNumber(self.config, "cabCompanyPromptMaxActivationDistance", 14), 1)
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute(REQUEST_PROMPT_ATTRIBUTE, true)
	prompt:SetAttribute(REQUEST_ACTION_ATTRIBUTE, action)
	prompt:SetAttribute(REQUEST_ZONE_ATTRIBUTE, zoneName)
end

function CabCompanyService:_installPrompts()
	local installedKeys = {}
	for _, definition in ipairs(PROMPT_DEFINITIONS) do
		local key = string.format("%s|%s", tostring(definition.zoneName), tostring(definition.action))
		if installedKeys[key] then
			warn("[cab87] Duplicate prompt definition skipped: " .. key)
		else
			installedKeys[key] = true
			self:_installPrompt(definition.zoneName, definition.action, definition.actionText)
		end
	end
end

function CabCompanyService:isShopEligible(player)
	local rootPart = getPlayerRootPart(player)
	if not rootPart then
		return false
	end

	local zone = self:_getValidZoneForAction("shop", rootPart.Position)
	if zone then
		return true
	end

	local zonesFolder = self:_getZonesFolder()
	if not zonesFolder and self:_isInFallbackCompanyRange(rootPart.Position) then
		return true
	end

	return false
end

function CabCompanyService:requestCab(player, actionOrPayload, taxiId)
	if not (typeof(player) == "Instance" and player:IsA("Player")) then
		return nil, "invalidPlayer"
	end

	if not self:_canRequest(player) then
		return nil, "cooldown"
	end

	local payload = getPayload(actionOrPayload, taxiId)
	local action = normalizeAction(payload.action)
	if action == "shop" then
		return nil, "invalidAction"
	end
	local isValid, reason, zone = self:_validateRequest(player, action)
	if not isValid then
		warn("[cab87] Rejected cab request from " .. player.Name .. ": " .. tostring(reason))
		return nil, reason
	end

	local resolvedTaxiId = self:_resolveTaxiId(player, payload.taxiId)
	local spawnPose = self:_getSpawnPose()
	local handle, created
	if action == "recover" then
		handle, created = self.taxiService:recoverCabForPlayer(player, resolvedTaxiId, spawnPose, {
			world = self.world,
		})
	else
		handle, created = self.taxiService:spawnCabForPlayer(player, resolvedTaxiId, spawnPose, {
			world = self.world,
		})
	end

	self:_markCabRequest(handle, action, zone)
	if handle and self.onCabReady then
		self.onCabReady(handle, {
			action = action,
			player = player,
			taxiId = resolvedTaxiId,
			created = created,
			spawnPose = spawnPose,
			zone = zone,
		})
	end

	return handle, if created then action else "existing"
end

function CabCompanyService:start()
	if self.started then
		return
	end
	self.started = true

	self:_installPrompts()

	local requestCabRemote = self.remotes.requestCab
	if requestCabRemote then
		self:_trackConnection(requestCabRemote.OnServerEvent:Connect(function(player, actionOrPayload, taxiId)
			local ok, err = pcall(function()
				self:requestCab(player, actionOrPayload, taxiId)
			end)
			if not ok then
				warn("[cab87] Cab request failed: " .. tostring(err))
			end
		end))
	end

	self:_trackConnection(Players.PlayerRemoving:Connect(function(player)
		self.lastRequestAtByUserId[player.UserId] = nil
	end))
end

function CabCompanyService:stop()
	for _, connection in ipairs(self.connections) do
		connection:Disconnect()
	end
	table.clear(self.connections)
	table.clear(self.lastRequestAtByUserId)
	self.started = false
end

return CabCompanyService
