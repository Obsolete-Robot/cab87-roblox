local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(shared:WaitForChild("Config"))
local Remotes = require(shared:WaitForChild("Remotes"))

local CabCompanyController = {}

local REQUEST_PROMPT_ATTRIBUTE = "Cab87CabRequestPrompt"
local REQUEST_ACTION_ATTRIBUTE = "Cab87CabRequestAction"
local REQUEST_ZONE_ATTRIBUTE = "Cab87CabRequestZone"

local player = Players.LocalPlayer

local function isCabRequestPrompt(prompt)
	return prompt
		and prompt:IsA("ProximityPrompt")
		and prompt:GetAttribute(REQUEST_PROMPT_ATTRIBUTE) == true
end

local function getSelectedTaxiId()
	local attributeName = Config.carSelectedTaxiIdAttribute or "Cab87SelectedTaxiId"
	local taxiId = player:GetAttribute(attributeName)
	if type(taxiId) == "string" and taxiId ~= "" then
		return taxiId
	end

	return nil
end

function CabCompanyController.start()
	local controller = {
		connections = {},
	}

	local remoteName = Remotes.getClientToServerName("requestCab")
	local requestCabRemote = ReplicatedStorage:WaitForChild(remoteName, 10)
	if not (requestCabRemote and requestCabRemote:IsA("RemoteEvent")) then
		warn("[cab87] Request cab remote is unavailable")
		return controller
	end

	local function connect(signal, callback)
		local connection = signal:Connect(callback)
		table.insert(controller.connections, connection)
		return connection
	end

	connect(ProximityPromptService.PromptTriggered, function(prompt)
		if not isCabRequestPrompt(prompt) then
			return
		end

		requestCabRemote:FireServer({
			action = prompt:GetAttribute(REQUEST_ACTION_ATTRIBUTE),
			zoneName = prompt:GetAttribute(REQUEST_ZONE_ATTRIBUTE),
			taxiId = getSelectedTaxiId(),
		})
	end)

	function controller:destroy()
		for _, connection in ipairs(self.connections) do
			connection:Disconnect()
		end
		table.clear(self.connections)
	end

	return controller
end

return CabCompanyController
