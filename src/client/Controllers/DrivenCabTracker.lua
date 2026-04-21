local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local DrivenCabTracker = {}

local player = Players.LocalPlayer

function DrivenCabTracker.getHumanoid()
	local character = player.Character
	if not character then
		return nil
	end

	return character:FindFirstChildOfClass("Humanoid")
end

function DrivenCabTracker.getCabFromSeat(seat)
	if not seat or not seat:IsA("VehicleSeat") or seat.Name ~= "DriverSeat" then
		return nil
	end

	local cab = seat.Parent
	if not cab or not cab:IsA("Model") or cab.Name ~= "Cab87Taxi" then
		return nil
	end

	return cab
end

function DrivenCabTracker.findCabOccupiedBy(humanoid)
	if not humanoid then
		return nil
	end

	for _, descendant in ipairs(Workspace:GetDescendants()) do
		if descendant:IsA("VehicleSeat")
			and descendant.Name == "DriverSeat"
			and descendant.Occupant == humanoid
		then
			return DrivenCabTracker.getCabFromSeat(descendant)
		end
	end

	return nil
end

function DrivenCabTracker.getDrivenCab()
	local humanoid = DrivenCabTracker.getHumanoid()
	if not humanoid then
		return nil
	end

	local seat = humanoid.SeatPart
	if seat and seat.Occupant == humanoid then
		return DrivenCabTracker.getCabFromSeat(seat)
	end

	return DrivenCabTracker.findCabOccupiedBy(humanoid)
end

return DrivenCabTracker
