local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CabVisuals = require(script.Parent:WaitForChild("CabVisuals"))
local DrivenCabTracker = require(script.Parent:WaitForChild("Controllers"):WaitForChild("DrivenCabTracker"))

local controllers = {}
local knownCabs = {}
local refreshAccumulator = 0

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

	local drivenCab = DrivenCabTracker.getDrivenCab()
	for cab in pairs(knownCabs) do
		if cab.Parent then
			updateCab(cab, drivenCab, dt)
		else
			destroyController(cab)
			knownCabs[cab] = nil
		end
	end
end)
