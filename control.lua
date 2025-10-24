local modName = "Alarm-Event"

local function __isStorageSafe(data, assumeRegisteredMT)
	local function helper(helperData, helperARMT, visited)
		if helperData and type(helperData) == "function" then return false end
		if not helperData or helperData and type(helperData) ~= "table" then return true end
		if not helperARMT and getmetatable(helperData) ~= nil then return false end
		visited[helperData] = true
		for _key_, value in pairs(helperData) do
			if not visited[_key_] and not helper(_key_, helperARMT, visited) then return false end
			if not visited[value] and not helper(value, helperARMT, visited) then return false end
		end
		return true
	end
	return helper(data, not not assumeRegisteredMT, {})
end

local function __init()
	storage.__wakeTickArray = {}
	storage.__eventIDsArray = {}
end

local function __returnObject(eventObject)
	return eventObject and {wakeTick = eventObject.wakeTick, eventID = eventObject.eventID, anon = not eventObject.registered} or nil
end

local function __remove(eventID, identifier)
	if not eventID then return nil end
	local eventObject = storage.__eventIDsArray[eventID]
	if not eventObject then return nil end
	if identifier and eventObject.registered then
		eventObject.registered[identifier] = nil
	end
	if not identifier or eventObject.registered and table_size(eventObject.registered) == 0 then
		storage.__wakeTickArray[eventObject.wakeTick] = nil
		storage.__eventIDsArray[eventObject.eventID]  = nil
		script.on_nth_tick(eventObject.wakeTick, nil)
	end
	return eventObject
end

local function __callbacker(NthTickEventData)
	local eventData = storage.__wakeTickArray[NthTickEventData.tick]
	if eventData and eventData.eventID then
		local data = {name = eventData.eventID, tick = NthTickEventData.tick, mod_name = modName}
		__remove(data.eventID)
		script.raise_event(data.name, data)
	end
end

local function __register(wakeTick, interface)
	if not wakeTick or type(wakeTick) ~= "number" or wakeTick <= game.tick then return nil end
	if interface and type(interface) ~= "string" then return nil end
	local eventObject = storage.__wakeTickArray[wakeTick] or {wakeTick = wakeTick, eventID = script.generate_event_name(), registerees = {}}
	if interface and eventObject.registerees then
		eventObject.registerees[interface] = true
	else
		eventObject.registerees = nil
	end
	storage.__wakeTickArray[wakeTick]            = eventObject
	storage.__eventIDsArray[eventObject.eventID] = eventObject
	script.on_nth_tick(wakeTick, __callbacker)
	return eventObject
end

local function __loader()
	for tick, _ in pairs(storage.__wakeTickArray) do
		script.on_nth_tick(tick, __callbacker)
	end
end

local function __setAlarm(timeInput, identifier)
	if timeInput and type(timeInput) == "table" then
		if not timeInput.delay and not timeInput.millis and not timeInput.seconds and not timeInput.tick then return nil end
		while not timeInput.tick do
			if timeInput.delay and type(timeInput.delay) == "number" then
				timeInput.tick = math.max(timeInput.delay, 1) + (game and game.tick or 0)
			elseif timeInput.delay then return nil end
			if timeInput.millis and type(timeInput.millis) == "number" then
				timeInput.delay = math.floor((timeInput.millis * 3 / 50) + 0.5)
			elseif timeInput.millis then return nil end
			if timeInput.seconds and type(timeInput.seconds) == "number" then
				timeInput.millis = timeInput.seconds * 1000
			elseif timeInput.seconds then return nil end
		end
		if type(timeInput.tick) ~= "number" then return nil end
		timeInput = timeInput.tick
	end
	if identifier and type(identifier) ~= "string" then return nil end
	if not timeInput or type(timeInput) ~= "number" then error("setAlarm called with invalid delay {"..serpent.line(timeInput).."}") end
	return __returnObject(__register(timeInput, identifier))
end

local function __getAlarm(eventID)
	if eventID and type(eventID) == "number" then eventID = {eventID = eventID} end
	if eventID and type(eventID) == "table" then
		if eventID.eventID then
			return __returnObject(storage.__eventIDsArray[eventID.eventID])
		elseif eventID.tick then
			return __returnObject(storage.__wakeTickArray[eventID.tick])
		end
	end
end

local function __delAlarm(eventID, identifier)
	if not eventID or type(eventID) ~= "number" or not identifier or type(identifier) ~= "string" then return nil end
	return __returnObject(__remove(eventID, identifier))
end

local selfInterfaceName = modName
local selfInterfaceFunc = {
	setAlarm = __setAlarm,
	delAlarm = __delAlarm,
	getAlarm = __getAlarm,
}

if script.mod_name == modName and not remote.interfaces[selfInterfaceName] then
	script.on_init(__init)
	script.on_load(__loader)

	remote.add_interface(selfInterfaceName, selfInterfaceFunc)
elseif script.mod_name == modName and remote.interfaces[selfInterfaceName] then
	error("Some other mod created an interface with the same name. Please send the mod developer a copy of your mod list so they can find the conflict.")
elseif script.mod_name ~= modName and remote.interfaces[selfInterfaceName] then
	local module = {
		interfaceName = selfInterfaceName,
		interfaceFunc = {},
		reverseFnName = {},
		isStorageSafe = __isStorageSafe,
	}
	for name, _ in pairs(selfInterfaceFunc) do
		local shortName = string.match(name, "^([%u%l][%u%l][%u%l])Alarm$")
		module.interfaceFunc[name] = shortName or true
		if shortName then
			module[shortName] = function(...) return remote.call(selfInterfaceName, name, ...) end
			module.reverseFnName[shortName] = name
		end
	end
	return module
else
	error("I don't know how you got here, you can only get here if my mod hasn't created the interface. This should only be possible if some mod unregistered my interface. Please send your mod list to me (the mod dev).")
end