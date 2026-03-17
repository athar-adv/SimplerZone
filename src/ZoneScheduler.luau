--!optimize 2
local RunService = game:GetService("RunService")
local ZoneScheduler = {}
local globalScheduler = nil

function ZoneScheduler.getGlobal()
	if not globalScheduler then
		globalScheduler = {
			dirtyParts = {},       -- {[part]       = {[listener] = {owner=, zone=}}}
			dirtyModels = {},      -- {[model]      = {[listener] = {[zone] = true}}}
			dirtyPlayers = {},     -- {[player]     = {[listener] = {[zone] = true}}}
			dirtyAttachments = {}, -- {[attachment] = {[listener] = {[zone] = true}}}
			dirtyPVInstances = {}, -- {[pvi]        = {[listener] = {[zone] = true}}}
			callbacks = {},
			listeners = {},
			trackedModels = {},      -- {[model]  = {[listener] = {[zone] = true}}}
			trackedPlayers = {},     -- {[player] = {[listener] = {[zone] = true}}}
			trackedPVInstances = {}, -- {[pvi]    = {[listener] = {[zone] = true}}}
			modelCache = {},
			playerCache = {},
			pvinstanceCache = {},
			connection = nil,
		}

		globalScheduler.connection = RunService.PostSimulation:Connect(function()
			local callbacks = globalScheduler.callbacks

			-- Check all tracked models for changes
			for model, listeners in globalScheduler.trackedModels do
				if not model:IsDescendantOf(game) then
					globalScheduler.trackedModels[model] = nil
					globalScheduler.modelCache[model] = nil
					continue
				end

				local success, cf, size = pcall(function()
					return model:GetBoundingBox()
				end)

				if success then
					local cache = globalScheduler.modelCache[model]
					if not cache or cf ~= cache.cf or size ~= cache.size then
						globalScheduler.modelCache[model] = {cf = cf, size = size}

						for listener, zones in listeners do
							for zone in zones do
								if not globalScheduler.dirtyModels[model] then
									globalScheduler.dirtyModels[model] = {}
								end
								if not globalScheduler.dirtyModels[model][listener] then
									globalScheduler.dirtyModels[model][listener] = {}
								end
								globalScheduler.dirtyModels[model][listener][zone] = true
							end
						end
					end
				end
			end

			-- Check all tracked players for changes
			for player, listeners in globalScheduler.trackedPlayers do
				local character = player.Character
				if not character or not character:IsDescendantOf(game) then
					continue
				end

				local success, cf, size = pcall(function()
					return character:GetBoundingBox()
				end)

				if success then
					local cache = globalScheduler.playerCache[player]
					if not cache or cf ~= cache.cf or size ~= cache.size then
						globalScheduler.playerCache[player] = {cf = cf, size = size}

						for listener, zones in listeners do
							for zone in zones do
								if not globalScheduler.dirtyPlayers[player] then
									globalScheduler.dirtyPlayers[player] = {}
								end
								if not globalScheduler.dirtyPlayers[player][listener] then
									globalScheduler.dirtyPlayers[player][listener] = {}
								end
								globalScheduler.dirtyPlayers[player][listener][zone] = true
							end
						end
					end
				end
			end

			-- Check all tracked PVInstances for changes
			for pvi, listeners in globalScheduler.trackedPVInstances do
				if not pvi:IsDescendantOf(game) then
					globalScheduler.trackedPVInstances[pvi] = nil
					globalScheduler.pvinstanceCache[pvi] = nil
					continue
				end

				local success, cf, size = pcall(function()
					if pvi:IsA("Model") or pvi:IsA("BasePart") then
						return pvi:GetBoundingBox()
					else
						local pivot = pvi:GetPivot()
						return pivot, Vector3.zero
					end
				end)

				if success then
					local cache = globalScheduler.pvinstanceCache[pvi]
					if not cache or cf ~= cache.cf or size ~= cache.size then
						globalScheduler.pvinstanceCache[pvi] = {cf = cf, size = size}

						for listener, zones in listeners do
							for zone in zones do
								if not globalScheduler.dirtyPVInstances[pvi] then
									globalScheduler.dirtyPVInstances[pvi] = {}
								end
								if not globalScheduler.dirtyPVInstances[pvi][listener] then
									globalScheduler.dirtyPVInstances[pvi][listener] = {}
								end
								globalScheduler.dirtyPVInstances[pvi][listener][zone] = true
							end
						end
					end
				end
			end

			-- Process dirty parts
			for part, listeners in globalScheduler.dirtyParts do
				for listener, entry in listeners do
					if listener.data.stopped then continue end
					if callbacks.checkPart then
						callbacks.checkPart(listener, entry.zone, part, entry.owner)
					end
				end
			end
			table.clear(globalScheduler.dirtyParts)

			-- Process dirty attachments
			for attachment, listeners in globalScheduler.dirtyAttachments do
				for listener, zones in listeners do
					if listener.data.stopped then continue end
					if callbacks.checkAttachment then
						for zone in zones do
							callbacks.checkAttachment(listener, zone, attachment)
						end
					end
				end
			end
			table.clear(globalScheduler.dirtyAttachments)

			-- Process dirty models
			for model, listeners in globalScheduler.dirtyModels do
				for listener, zones in listeners do
					if listener.data.stopped then continue end
					if callbacks.checkModel then
						for zone in zones do
							callbacks.checkModel(listener, zone, model)
						end
					end
				end
			end
			table.clear(globalScheduler.dirtyModels)

			-- Process dirty players
			for player, listeners in globalScheduler.dirtyPlayers do
				for listener, zones in listeners do
					if listener.data.stopped then continue end
					if callbacks.checkPlayer then
						for zone in zones do
							callbacks.checkPlayer(listener, zone, player)
						end
					end
				end
			end
			table.clear(globalScheduler.dirtyPlayers)

			-- Process dirty PVInstances
			for pvi, listeners in globalScheduler.dirtyPVInstances do
				for listener, zones in listeners do
					if listener.data.stopped then continue end
					if callbacks.checkPVInstance then
						for zone in zones do
							callbacks.checkPVInstance(listener, zone, pvi)
						end
					end
				end
			end
			table.clear(globalScheduler.dirtyPVInstances)
		end)
	end
	return globalScheduler
end

function ZoneScheduler.markPartDirty(part: BasePart, listener: any, owner: Model | Player | nil, zone: any)
	local scheduler = ZoneScheduler.getGlobal()
	if not scheduler.dirtyParts[part] then
		scheduler.dirtyParts[part] = {}
	end
	scheduler.dirtyParts[part][listener] = {owner = owner, zone = zone}
end

function ZoneScheduler.markAttachmentDirty(attachment: Attachment, listener: any, zone: any)
	local scheduler = ZoneScheduler.getGlobal()
	if not scheduler.dirtyAttachments[attachment] then
		scheduler.dirtyAttachments[attachment] = {}
	end
	if not scheduler.dirtyAttachments[attachment][listener] then
		scheduler.dirtyAttachments[attachment][listener] = {}
	end
	scheduler.dirtyAttachments[attachment][listener][zone] = true
end

function ZoneScheduler.markModelDirty(model: Model, listener: any, zone: any)
	local scheduler = ZoneScheduler.getGlobal()
	if not scheduler.dirtyModels[model] then
		scheduler.dirtyModels[model] = {}
	end
	if not scheduler.dirtyModels[model][listener] then
		scheduler.dirtyModels[model][listener] = {}
	end
	scheduler.dirtyModels[model][listener][zone] = true
end

function ZoneScheduler.markPlayerDirty(player: Player, listener: any, zone: any)
	local scheduler = ZoneScheduler.getGlobal()
	if not scheduler.dirtyPlayers[player] then
		scheduler.dirtyPlayers[player] = {}
	end
	if not scheduler.dirtyPlayers[player][listener] then
		scheduler.dirtyPlayers[player][listener] = {}
	end
	scheduler.dirtyPlayers[player][listener][zone] = true
end

function ZoneScheduler.markPVInstanceDirty(pvi: PVInstance, listener: any, zone: any)
	local scheduler = ZoneScheduler.getGlobal()
	if not scheduler.dirtyPVInstances[pvi] then
		scheduler.dirtyPVInstances[pvi] = {}
	end
	if not scheduler.dirtyPVInstances[pvi][listener] then
		scheduler.dirtyPVInstances[pvi][listener] = {}
	end
	scheduler.dirtyPVInstances[pvi][listener][zone] = true
end

function ZoneScheduler.trackModel(model: Model, listener: any, zone: any)
	local scheduler = ZoneScheduler.getGlobal()
	if not scheduler.trackedModels[model] then
		scheduler.trackedModels[model] = {}
	end
	if not scheduler.trackedModels[model][listener] then
		scheduler.trackedModels[model][listener] = {}
	end
	scheduler.trackedModels[model][listener][zone] = true
end

function ZoneScheduler.untrackModel(model: Model, listener: any, zone: any?)
	local scheduler = ZoneScheduler.getGlobal()
	if not scheduler.trackedModels[model] then return end
	if zone then
		if scheduler.trackedModels[model][listener] then
			scheduler.trackedModels[model][listener][zone] = nil
			if not next(scheduler.trackedModels[model][listener]) then
				scheduler.trackedModels[model][listener] = nil
			end
		end
	else
		scheduler.trackedModels[model][listener] = nil
	end
	if not next(scheduler.trackedModels[model]) then
		scheduler.trackedModels[model] = nil
		scheduler.modelCache[model] = nil
	end
end

function ZoneScheduler.trackPlayer(player: Player, listener: any, zone: any)
	local scheduler = ZoneScheduler.getGlobal()
	if not scheduler.trackedPlayers[player] then
		scheduler.trackedPlayers[player] = {}
	end
	if not scheduler.trackedPlayers[player][listener] then
		scheduler.trackedPlayers[player][listener] = {}
	end
	scheduler.trackedPlayers[player][listener][zone] = true
end

function ZoneScheduler.untrackPlayer(player: Player, listener: any, zone: any?)
	local scheduler = ZoneScheduler.getGlobal()
	if not scheduler.trackedPlayers[player] then return end
	if zone then
		if scheduler.trackedPlayers[player][listener] then
			scheduler.trackedPlayers[player][listener][zone] = nil
			if not next(scheduler.trackedPlayers[player][listener]) then
				scheduler.trackedPlayers[player][listener] = nil
			end
		end
	else
		scheduler.trackedPlayers[player][listener] = nil
	end
	if not next(scheduler.trackedPlayers[player]) then
		scheduler.trackedPlayers[player] = nil
		scheduler.playerCache[player] = nil
	end
end

function ZoneScheduler.trackPVInstance(pvi: PVInstance, listener: any, zone: any)
	local scheduler = ZoneScheduler.getGlobal()
	if not scheduler.trackedPVInstances[pvi] then
		scheduler.trackedPVInstances[pvi] = {}
	end
	if not scheduler.trackedPVInstances[pvi][listener] then
		scheduler.trackedPVInstances[pvi][listener] = {}
	end
	scheduler.trackedPVInstances[pvi][listener][zone] = true
end

function ZoneScheduler.untrackPVInstance(pvi: PVInstance, listener: any, zone: any?)
	local scheduler = ZoneScheduler.getGlobal()
	if not scheduler.trackedPVInstances[pvi] then return end
	if zone then
		if scheduler.trackedPVInstances[pvi][listener] then
			scheduler.trackedPVInstances[pvi][listener][zone] = nil
			if not next(scheduler.trackedPVInstances[pvi][listener]) then
				scheduler.trackedPVInstances[pvi][listener] = nil
			end
		end
	else
		scheduler.trackedPVInstances[pvi][listener] = nil
	end
	if not next(scheduler.trackedPVInstances[pvi]) then
		scheduler.trackedPVInstances[pvi] = nil
		scheduler.pvinstanceCache[pvi] = nil
	end
end

function ZoneScheduler.registerCallbacks(callbacks: any)
	local scheduler = ZoneScheduler.getGlobal()
	scheduler.callbacks = callbacks
end

function ZoneScheduler.registerListener(listener: any)
	local scheduler = ZoneScheduler.getGlobal()
	table.insert(scheduler.listeners, listener)
end

function ZoneScheduler.unregisterListener(listener: any)
	local scheduler = ZoneScheduler.getGlobal()
	local idx = table.find(scheduler.listeners, listener)
	if idx then table.remove(scheduler.listeners, idx) end

	for part, listeners in scheduler.dirtyParts do
		listeners[listener] = nil
	end
	for attachment, listeners in scheduler.dirtyAttachments do
		listeners[listener] = nil
	end
	for model, listeners in scheduler.dirtyModels do
		listeners[listener] = nil
	end
	for player, listeners in scheduler.dirtyPlayers do
		listeners[listener] = nil
	end
	for pvi, listeners in scheduler.dirtyPVInstances do
		listeners[listener] = nil
	end

	for model, listeners in scheduler.trackedModels do
		listeners[listener] = nil
		if not next(listeners) then
			scheduler.trackedModels[model] = nil
			scheduler.modelCache[model] = nil
		end
	end
	for player, listeners in scheduler.trackedPlayers do
		listeners[listener] = nil
		if not next(listeners) then
			scheduler.trackedPlayers[player] = nil
			scheduler.playerCache[player] = nil
		end
	end
	for pvi, listeners in scheduler.trackedPVInstances do
		listeners[listener] = nil
		if not next(listeners) then
			scheduler.trackedPVInstances[pvi] = nil
			scheduler.pvinstanceCache[pvi] = nil
		end
	end
end

function ZoneScheduler.markZoneDirtyForListeners(zone: any)
	local scheduler = ZoneScheduler.getGlobal()
	zone:rebuild()
	for _, listener in scheduler.listeners do
		if not table.find(listener.zones, zone) then continue end

		for part, _ in listener.data.partConnections do
			ZoneScheduler.markPartDirty(part, listener, nil, zone)
		end
		for model, _ in listener.data.modelConnections do
			ZoneScheduler.markModelDirty(model, listener, zone)
		end
		for player, _ in listener.data.playerConnections do
			ZoneScheduler.markPlayerDirty(player, listener, zone)
		end
		for attachment, _ in listener.data.attachmentConnections do
			ZoneScheduler.markAttachmentDirty(attachment, listener, zone)
		end
	end
end

return ZoneScheduler