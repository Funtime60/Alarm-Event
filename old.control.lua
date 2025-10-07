local modName = "Set-Timeout"

local function flatten_lookup_table(lookup_table)
	local flat_result = {}

	local function recurse(current_table)
		for _, value in pairs(current_table) do
			if type(value) == "table" and not value.identifier then
				recurse(value)
			elseif type(value) == "table" then
				flat_result[value.identifier] = value
			end
		end
	end

	recurse(lookup_table)
	return flat_result
end

local function init()
	storage.__wakeTickArray = {}
	storage.interfaceArray = {}
	storage.__eventIDsArray = {}
	storage.uniqueNumber   = 0
end

local function __uniqueID()
	local value = storage.uniqueNumber
	storage.uniqueNumber = value + 1
	return value
end

local function __remove(identifier)
	local totalObject   = storage.__eventIDsArray[identifier]
	if not totalObject then return nil end
	local wakeTick      = totalObject.wakeTick
	local interfaceName = totalObject.interfaceName
	local functionName  = totalObject.functionName
	storage.__wakeTickArray[wakeTick]                   [identifier] = nil
	storage.interfaceArray[interfaceName][functionName][identifier] = nil
	storage.__eventIDsArray                             [identifier] = nil
	if table_size(storage.__wakeTickArray[wakeTick]) == 0 then
		storage.__wakeTickArray[wakeTick] = nil
	end
	if table_size(storage.interfaceArray[interfaceName][functionName]) == 0 then
		storage.interfaceArray[interfaceName][functionName] = nil
	end
	if table_size(storage.interfaceArray[interfaceName]) == 0 then
		storage.interfaceArray[interfaceName] = nil
	end
	return totalObject
end

local function callbacker(NthTickEventData)
	script.on_nth_tick(NthTickEventData.nth_tick, nil)
	local identifiersToRemove = {}
	for _, totalObject in pairs(storage.__wakeTickArray[NthTickEventData.nth_tick]) do
		if remote.interfaces[totalObject.interfaceName] and remote.interfaces[totalObject.interfaceName][totalObject.functionName] then
			remote.call(totalObject.interfaceName, totalObject.functionName, totalObject)
		else
			log("WARN: callback interface {["..totalObject.interfaceName.."]["..totalObject.functionName.."]} was not registered")
		end
		table.insert(identifiersToRemove, totalObject.identifier)
	end
	for _, identifier in ipairs(identifiersToRemove) do
		__remove(identifier)
	end
end

local function __register(wakeTick, interfaceName, functionName)
	if not wakeTick or not interfaceName or not functionName then return nil end
	if wakeTick <= game.tick then return nil end
	local identifier = __uniqueID()
	if not storage.__wakeTickArray[wakeTick] then
		storage.__wakeTickArray[wakeTick] = {}
	end
	if not storage.interfaceArray[interfaceName] then
		storage.interfaceArray[interfaceName] = {}
	end
	if not storage.interfaceArray[interfaceName][functionName] then
		storage.interfaceArray[interfaceName][functionName] = {}
	end
	local totalObject = {wakeTick = wakeTick, interfaceName = interfaceName, functionName = functionName, identifier = identifier}
	storage.__wakeTickArray[wakeTick]                   [identifier] = totalObject
	storage.interfaceArray[interfaceName][functionName][identifier] = totalObject
	storage.__eventIDsArray                             [identifier] = totalObject
	script.on_nth_tick(wakeTick, callbacker)
	return totalObject
end

local function __lookup(first, second, third)
	if first and type(first) == "number" then
		if second then
			return flatten_lookup_table(storage.__wakeTickArray[first][second])
		else
			return flatten_lookup_table(storage.__wakeTickArray[first])
		end
	elseif first and type(first) == "string" then
		if second then
			if third then
				return flatten_lookup_table(storage.interfaceArray[first][second][third])
			else
				return flatten_lookup_table(storage.interfaceArray[first][second])
			end
		else
			return flatten_lookup_table(storage.interfaceArray[first])
		end
	elseif first and type(first) == "table" and first.identifier then
		return {storage.__eventIDsArray[first.identifier]}
	else
		return nil
	end
end

local function clearOld()
	local identifiersToRemove = {}
	for interfaceName, functionArray in pairs(storage.interfaceArray) do
		if not remote.interfaces[interfaceName] then
			for _, totalObject in pairs(__lookup(interfaceName) or {}) do
				table.insert(identifiersToRemove, totalObject.identifier)
			end
		else
			for functionName, _ in pairs(functionArray) do
				if not remote.interfaces[interfaceName][functionName] then
					for _, totalObject in pairs(__lookup(interfaceName, functionName) or {}) do
						table.insert(identifiersToRemove, totalObject.identifier)
					end
				end
			end
		end
	end
	for _, identifier in ipairs(identifiersToRemove) do
		__remove(identifier)
	end
end

local function loader()
	for tick, _ in pairs(storage.__wakeTickArray) do
		script.on_nth_tick(tick, callbacker)
	end
end


local function __setTimeout(delay,  interfaceName, functionName)
	-- game.players[1].print(delay .. " - " .. interfaceName)
	return __register(game.tick + delay, interfaceName, functionName)
end
local function __setAlarm(wakeTick, interfaceName, functionName)
	return __register(wakeTick, interfaceName, functionName)
end
local function __clearTimeout(identifier)
	return __remove(identifier)
end
local function __getTimeouts(interfaceName)
	return __lookup(interfaceName)
end

local selfInterfaceName = "delay"
local selfInterfaceFunc = {
	setTimeout = __setTimeout,
	setAlarm = __setAlarm,
	clearTimeout = __clearTimeout,
	clearAlarm = __clearTimeout,
	getTimeouts = __getTimeouts,
	getAlarms = __getTimeouts,
}

if script.mod_name == modName and not remote.interfaces[selfInterfaceName] then
	script.on_init(init)
	script.on_configuration_changed(clearOld)
	script.on_load(loader)

	remote.add_interface(selfInterfaceName, selfInterfaceFunc)
	commands.add_command("dump", nil, function (commandData)
		local player = game.players[commandData.player_index]
		local print  = player.print
		print(serpent.block(storage))
	end)
elseif script.mod_name == modName and remote.interfaces[selfInterfaceName] then
	error("Some other mod created an interface with the same name. Please send the mod developer a copy of your mod list so they can find the conflict.")
elseif script.mod_name ~= modName and remote.interfaces[selfInterfaceName] then
	local function createCallbackInterface(callbackName, func)
		return remote.add_interface(callbackName, {[callbackName] = function(...)
			if storage.timeout and type(storage.timeout) == "table" and storage.timeout[callbackName] then storage.timeout[callbackName] = nil end
			if remote.interfaces[callbackName] then remote.remove_interface(callbackName) end
			return func(...)
		end})
	end
	local function generateCallbackInterface(func)
		local callbackName
		repeat
			callbackName = "delay-auto-callback-" .. math.random(10000, 99999)
		until not remote.interfaces[callbackName]
		createCallbackInterface(callbackName, func)
		return {name = callbackName, func = func}
	end
	local revSelfInterfaceFunc = {
		[__setTimeout]   = "setTimeoutReverseLookup",
		[__setAlarm]     = "setAlarmReverseLookup",
		[__clearTimeout] = "clearTimeoutReverseLookup",
		[__getTimeouts]  = "getTimeoutReverseLookup",
	}
	for funcName, func in pairs(selfInterfaceFunc) do
		revSelfInterfaceFunc[revSelfInterfaceFunc[func] or "no"] = funcName
		revSelfInterfaceFunc[func] = nil
		revSelfInterfaceFunc["no"] = nil
	end
	local localFunctionLost = "LOCAL FUNCTION LOST"
	local function storeCallback(returnData, localG)
		if storage.timeout and type(storage.timeout) == "table" then
			---@diagnostic disable-next-line: undefined-global
			if localG and type(localG) == "table" and localG.__reverse and localG.__reverse[returnData.callbackFunc] then
				---@diagnostic disable-next-line: undefined-global
				returnData.callbackFunc = localG.__reverse[returnData.callbackFunc]
			end
			if type(returnData.callbackFunc) ~= "string" then
				for key, value in pairs(_G) do
					if value == returnData.callbackFunc then
						returnData.callbackFunc = key
						break
					end
				end
			end
			if type(returnData.callbackFunc) == "string" then
				storage.timeout[returnData.callbackName] = returnData
			end
		end
		return returnData
	end
	local function loadCallbacks(self)
		if storage.timeout and type(storage.timeout) == "table" then
			for _, returnData in pairs(storage.timeout) do
				if returnData.callbackFunc ~= localFunctionLost then
					---@diagnostic disable-next-line: undefined-global
					if self and self.localG and type(self.localG) == "table" then
						---@diagnostic disable-next-line: undefined-global
						createCallbackInterface(returnData.callbackName, localG[returnData.callbackFunc])
					elseif _G[returnData.callbackFunc] then
						createCallbackInterface(returnData.callbackName, _G[returnData.callbackFunc])
					else
						log("WARN: __local_global function {"..returnData.callbackFunc.."} was not defined")
					end
				else
					log("WARN: callback function for {"..returnData.callbackName.."} was lost on save, cannot re-link")
				end
			end
		end
	end
	local module = {
		name = selfInterfaceName,
		func = {},
		load = loadCallbacks,
		init = function(self, localG)
			storage.timeout = {}
			if self and localG then
				game.players[1].print(serpent.block(localG))
				game.players[1].print(serpent.block(self))
				self.localG = localG
			end
		end,
		seconds = function(seconds) return seconds * 60 end,
		millis  = function(millis, roundType)
			if millis == nil and roundType then
				millis = roundType
				roundType = nil
			elseif millis then
				roundType = roundType or 0
			end
			local raw = millis * 3 / 50
			if roundType > 0 then
				return math.max(math.ceil(raw), 1)
			end
			if roundType == 0 then
				return math.max(math.floor(raw + 0.5), 1)
			end
			if roundType < 0 then
				return math.max(math.floor(raw), 1)
			end
		end,
		setTimeout = function(self, delay, func)
			if not func then
				func = delay
				delay = self
				self = nil
			end
			local callbackInterface = generateCallbackInterface(func)
			return storeCallback({callbackName = callbackInterface.name, callbackFunc = callbackInterface.func, timeoutData = remote.call(selfInterfaceName, revSelfInterfaceFunc["setTimeoutReverseLookup"], delay, callbackInterface.name, callbackInterface.name)}, self.localG)
		end,
		setAlarm = function(self, wakeTick, func)
			if not func then
				func = wakeTick
				wakeTick = self
				self = nil
			end
			local callbackInterface = generateCallbackInterface(func)
			return storeCallback({callbackName = callbackInterface.name, callbackFunc = callbackInterface.func, timeoutData = remote.call(selfInterfaceName, revSelfInterfaceFunc["setAlarmReverseLookup"], wakeTick, callbackInterface.name, callbackInterface.name)}, self.localG)
		end,
		clearTimeout = function(identifier)
			return remote.call(selfInterfaceName, revSelfInterfaceFunc["clearTimeoutReverseLookup"], identifier)
		end,
		getTimeouts = function(interfaceName)
			return remote.call(selfInterfaceName, revSelfInterfaceFunc["getTimeoutReverseLookup"], interfaceName)
		end,
	}
	module.clearAlarm = module.clearTimeout
	module.getAlarms = module.getTimeouts
	for key, _ in pairs(selfInterfaceFunc) do
		module.func[key] = key
	end
	return module
else
	error("I don't know how you got here, you can only get here if my mod hasn't created the interface. This should only be possible if some mod unregistered my interface. Please send your mod list to me (the mod dev).")
end