local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CabVisuals = require(script.Parent:WaitForChild("CabVisuals"))

local player = Players.LocalPlayer
local controllers = {}
local knownCabs = {}
local refreshAccumulator = 0

local function getHumanoid()
	local character = player.Character
	if not character then
		return nil
	end

	return character:FindFirstChildOfClass("Humanoid")
end

local function getCabFromSeat(seat)
	if not seat or not seat:IsA("VehicleSeat") or seat.Name ~= "DriverSeat" then
		return nil
	end

	local cab = seat.Parent
	if not cab or not cab:IsA("Model") or cab.Name ~= "Cab87Taxi" then
		return nil
	end

	return cab
end

local function findCabOccupiedBy(humanoid)
	if not humanoid then
		return nil
	end

	for _, descendant in ipairs(Workspace:GetDescendants()) do
		if descendant:IsA("VehicleSeat")
			and descendant.Name == "DriverSeat"
			and descendant.Occupant == humanoid
		then
			return getCabFromSeat(descendant)
		end
	end

	return nil
end

local function getDrivenCab()
	local humanoid = getHumanoid()
	local seat = humanoid and humanoid.SeatPart
	return getCabFromSeat(seat) or findCabOccupiedBy(humanoid)
end

local function isCab(instance)
	return instance:IsA("Model") and instance.Name == "Cab87Taxi"
end

local function refreshCabs()
	local nextCabs = {}

	for _, descendant in ipairs(Workspace:GetDescendants()) do
		if isCab(descendant) then
			nextCabs[descendant] = true
		end
	end

	for cab in pairs(knownCabs) do
		if not nextCabs[cab] then
			local controller = controllers[cab]
			if controller then
				controller:destroy()
				controllers[cab] = nil
			end
		end
	end

	knownCabs = nextCabs
end

local function destroyController(cab)
	local controller = controllers[cab]
	if controller then
		controller:destroy()
		controllers[cab] = nil
	end
end

local function updateCab(cab, drivenCab, dt)
	if cab == drivenCab then
		destroyController(cab)
		return
	end

	local controller = controllers[cab]
	if not controller then
		controller = CabVisuals.new(cab, {
			parent = Workspace.CurrentCamera or Workspace,
		})
		controllers[cab] = controller
	else
		controller:setParent(Workspace.CurrentCamera or Workspace)
	end

	controller:update(CabVisuals.getCabTargetPivot(cab), dt)
end

refreshCabs()

RunService:BindToRenderStep("Cab87RemoteCabVisuals", Enum.RenderPriority.Camera.Value, function(dt)
	refreshAccumulator += dt
	if refreshAccumulator >= 0.5 then
		refreshAccumulator = 0
		refreshCabs()
	end

	local drivenCab = getDrivenCab()
	for cab in pairs(knownCabs) do
		if cab.Parent then
			updateCab(cab, drivenCab, dt)
		else
			destroyController(cab)
			knownCabs[cab] = nil
		end
	end
end)
