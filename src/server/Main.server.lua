local RunService = game:GetService("RunService")

local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Config"))
local MapGenerator = require(script.Parent:WaitForChild("MapGenerator"))

local function makePart(parent, props)
	local part = Instance.new("Part")
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in pairs(props) do
		part[key] = value
	end
	part.Parent = parent
	return part
end

local function createCab(world)
	local car = Instance.new("Model")
	car.Name = "Cab87Taxi"
	car.Parent = world

	local body = makePart(car, {
		Name = "Body",
		Size = Vector3.new(10, 2, 16),
		Position = Config.carSpawn,
		Color = Color3.fromRGB(255, 206, 38),
		Material = Enum.Material.SmoothPlastic,
	})

	makePart(car, {
		Name = "Roof",
		Size = Vector3.new(8, 1.5, 8),
		Position = Config.carSpawn + Vector3.new(0, 2, -1),
		Color = Color3.fromRGB(255, 227, 120),
		Material = Enum.Material.SmoothPlastic,
	})

	local seat = Instance.new("VehicleSeat")
	seat.Name = "DriverSeat"
	seat.Anchored = true
	seat.Size = Vector3.new(3.5, 1, 4)
	seat.Position = Config.carSpawn + Vector3.new(0, 1.5, 1)
	seat.Transparency = 0.2
	seat.Color = Color3.fromRGB(35, 35, 40)
	seat.MaxSpeed = 0
	seat.Torque = 0
	seat.TurnSpeed = 0
	seat.Parent = car

	makePart(car, {
		Name = "CabSign",
		Size = Vector3.new(3.2, 0.8, 1.4),
		Position = Config.carSpawn + Vector3.new(0, 3.4, -1),
		Color = Color3.fromRGB(255, 245, 170),
		Material = Enum.Material.Neon,
	})

	local wheelOffsets = {
		Vector3.new(4.4, -1.2, 5.6),
		Vector3.new(-4.4, -1.2, 5.6),
		Vector3.new(4.4, -1.2, -5.6),
		Vector3.new(-4.4, -1.2, -5.6),
	}

	for i, offset in ipairs(wheelOffsets) do
		local wheel = makePart(car, {
			Name = "Wheel" .. i,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(2.2, 1.4, 2.2),
			Position = Config.carSpawn + offset,
			Color = Color3.fromRGB(25, 25, 30),
			Material = Enum.Material.SmoothPlastic,
		})
		wheel.CFrame = wheel.CFrame * CFrame.Angles(0, 0, math.rad(90))
	end

	car.PrimaryPart = body
	car:PivotTo(CFrame.new(Config.carSpawn))

	for _, item in ipairs(car:GetDescendants()) do
		if item:IsA("BasePart") then
			item.Anchored = true
		end
	end

	return car, seat
end

local function runCarController(car, seat)
	local position = Config.carSpawn
	local yaw = 0
	local speed = 0

	local function dampToZero(value, amount)
		if math.abs(value) <= amount then
			return 0
		end
		return value - math.sign(value) * amount
	end

	RunService.Heartbeat:Connect(function(dt)
		local throttle = seat.ThrottleFloat
		local steer = seat.SteerFloat

		if throttle > 0 then
			speed = math.min(speed + Config.carAccel * throttle * dt, Config.carMaxForward)
		elseif throttle < 0 then
			if speed > 0 then
				speed = math.max(speed + Config.carBrake * throttle * dt, 0)
			else
				speed = math.max(speed + Config.carAccel * throttle * dt, -Config.carMaxReverse)
			end
		else
			speed = dampToZero(speed, Config.carDrag * dt)
		end

		if math.abs(speed) > Config.carMinTurnSpeed and math.abs(steer) > 0.01 then
			local turnScale = math.clamp(math.abs(speed) / Config.carMaxForward, 0.25, 1)
			yaw -= steer * Config.carTurnRate * turnScale * dt
		end

		local forward = Vector3.new(math.sin(yaw), 0, math.cos(yaw))
		position += forward * speed * dt

		car:PivotTo(CFrame.new(position) * CFrame.Angles(0, yaw, 0))
	end)
end

local world = MapGenerator.Generate()
local car, seat = createCab(world)
runCarController(car, seat)
