local DebugTuningService = {}
DebugTuningService.__index = DebugTuningService

local function normalizeTuningValue(value, property)
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return nil
	end

	local minValue = property.min
	local maxValue = property.max
	if type(minValue) ~= "number" or type(maxValue) ~= "number" then
		return nil
	end

	if maxValue < minValue then
		maxValue = minValue
	end

	value = math.clamp(value, minValue, maxValue)

	if type(property.step) == "number" and property.step > 0 then
		value = minValue + math.floor((value - minValue) / property.step + 0.5) * property.step
		value = math.clamp(value, minValue, maxValue)
	end

	return value
end

function DebugTuningService.new(options)
	options = options or {}

	return setmetatable({
		config = options.config or {},
		remote = options.remote,
		connections = {},
		listeners = {},
		propertiesByKey = {},
		defaultValues = {},
		started = false,
	}, DebugTuningService)
end

function DebugTuningService:onChanged(listener)
	if type(listener) ~= "function" then
		return function() end
	end

	table.insert(self.listeners, listener)
	local removed = false
	return function()
		if removed then
			return
		end
		removed = true

		for index = #self.listeners, 1, -1 do
			if self.listeners[index] == listener then
				table.remove(self.listeners, index)
				break
			end
		end
	end
end

function DebugTuningService:_emitChanged(key, value)
	for _, listener in ipairs(self.listeners) do
		local ok, err = pcall(listener, key, value)
		if not ok then
			warn("[cab87] Debug tuning listener failed: " .. tostring(err))
		end
	end
end

function DebugTuningService:_buildProperties()
	table.clear(self.propertiesByKey)
	table.clear(self.defaultValues)

	for _, property in ipairs(self.config.debugTuningProperties or {}) do
		if type(property) == "table" and type(property.key) == "string" then
			local currentValue = self.config[property.key]
			if type(currentValue) == "number" and normalizeTuningValue(currentValue, property) ~= nil then
				self.propertiesByKey[property.key] = property
				self.defaultValues[property.key] = currentValue
			end
		end
	end
end

function DebugTuningService:_getSnapshot()
	local snapshot = {}
	for key in pairs(self.propertiesByKey) do
		snapshot[key] = self.config[key]
	end
	return snapshot
end

function DebugTuningService:_setValue(key, value)
	self.config[key] = value
	self:_emitChanged(key, value)
end

function DebugTuningService:start()
	if self.started then
		return
	end
	self.started = true
	self:_buildProperties()

	if not self.remote then
		return
	end

	table.insert(self.connections, self.remote.OnServerEvent:Connect(function(player, action, key, value)
		if action == "Snapshot" then
			self.remote:FireClient(player, "Snapshot", self:_getSnapshot())
			return
		end

		if action == "ResetAll" then
			for resetKey, defaultValue in pairs(self.defaultValues) do
				self:_setValue(resetKey, defaultValue)
			end
			self.remote:FireAllClients("Snapshot", self:_getSnapshot())
			return
		end

		if type(key) ~= "string" then
			return
		end

		local property = self.propertiesByKey[key]
		if not property then
			return
		end

		if action == "Reset" then
			local defaultValue = self.defaultValues[key]
			self:_setValue(key, defaultValue)
			self.remote:FireAllClients("Set", key, defaultValue)
		elseif action == "Set" then
			local normalizedValue = normalizeTuningValue(value, property)
			if normalizedValue == nil then
				return
			end

			self:_setValue(key, normalizedValue)
			self.remote:FireAllClients("Set", key, normalizedValue)
		end
	end))
end

function DebugTuningService:stop()
	for _, connection in ipairs(self.connections) do
		connection:Disconnect()
	end
	table.clear(self.connections)
	self.started = false
end

return DebugTuningService
