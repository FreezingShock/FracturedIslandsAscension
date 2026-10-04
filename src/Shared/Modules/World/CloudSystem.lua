-- CloudSystem.lua (v20 - v17 Foundation + Sharp Position Changes + Emission Per Move)
-- Proven v17 emitter/attachment logic, now with:
-- - Sharp instant position jumps (discrete steps via floor'd noise)
-- - Emit(1) on every position change
-- Placed in ReplicatedStorage.Modules

local CloudConfig = require(
	game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("Config"):WaitForChild("CloudConfig")
)
local RunService = game:GetService("RunService")
local CloudSystem = {}

local _cloudParts = {}
local _emitterPool = {}
local _attachmentPool = {}
local _allEmitters = {}
local _lastLODCheck = tick()
local _activeClouds = 0
local _cloudCount = 0
local _heartbeatConn = nil
local _animationTime = tick()

-- ===== 3D PERLIN NOISE =====
local function hash3(x, y, z)
	local a = math.sin(x * 12.9898 + y * 78.233 + z * 45.164) * 43758.5453
	return a - math.floor(a)
end

local function noise3(x, y, z)
	local xi = math.floor(x)
	local yi = math.floor(y)
	local zi = math.floor(z)

	local xf = x - xi
	local yf = y - yi
	local zf = z - zi

	local u = xf * xf * (3 - 2 * xf)
	local v = yf * yf * (3 - 2 * yf)
	local w = zf * zf * (3 - 2 * zf)

	local n000 = hash3(xi, yi, zi)
	local n100 = hash3(xi + 1, yi, zi)
	local n010 = hash3(xi, yi + 1, zi)
	local n110 = hash3(xi + 1, yi + 1, zi)
	local n001 = hash3(xi, yi, zi + 1)
	local n101 = hash3(xi + 1, yi, zi + 1)
	local n011 = hash3(xi, yi + 1, zi + 1)
	local n111 = hash3(xi + 1, yi + 1, zi + 1)

	local ny0 = n000 * (1 - u) + n100 * u
	local ny1 = n010 * (1 - u) + n110 * u
	local nz0 = ny0 * (1 - v) + ny1 * v

	local ny0b = n001 * (1 - u) + n101 * u
	local ny1b = n011 * (1 - u) + n111 * u
	local nz1 = ny0b * (1 - v) + ny1b * v

	return nz0 * (1 - w) + nz1 * w
end

-- ===== POOL =====
local function acquireEmitterFromPool()
	for _, poolEntry in ipairs(_emitterPool) do
		if not poolEntry.inUse then
			poolEntry.inUse = true
			return poolEntry.emitter
		end
	end
	local newEmitter = Instance.new("ParticleEmitter")
	table.insert(_emitterPool, { emitter = newEmitter, inUse = true })
	return newEmitter
end

local function releaseEmitterToPool(emitter)
	for _, poolEntry in ipairs(_emitterPool) do
		if poolEntry.emitter == emitter then
			poolEntry.inUse = false
			emitter.Enabled = false
			break
		end
	end
end

local function acquireAttachmentFromPool(part)
	for _, poolEntry in ipairs(_attachmentPool) do
		if not poolEntry.inUse then
			poolEntry.inUse = true
			poolEntry.attachment.Parent = part
			return poolEntry.attachment
		end
	end
	local newAttachment = Instance.new("Attachment")
	table.insert(_attachmentPool, { attachment = newAttachment, inUse = true })
	newAttachment.Parent = part
	return newAttachment
end

local function releaseAttachmentToPool(attachment)
	for _, poolEntry in ipairs(_attachmentPool) do
		if poolEntry.attachment == attachment then
			poolEntry.inUse = false
			attachment.Parent = nil
			break
		end
	end
end

-- ===== APPLY TEMPLATE =====
local function applyTemplate(emitter, template)
	for prop, value in pairs(template) do
		if typeof(value) ~= "userdata" and prop ~= "Enabled" then
			pcall(function()
				emitter[prop] = value
			end)
		end
	end
	emitter.Rate = 0
end

-- ===== DYNAMIC SCALING =====
local function scaleEmitterByPart(emitter, partSize, baseTemplate)
	local partScale = math.min(partSize / 12, 3.5)
	partScale = math.max(partScale, 0.8)

	if baseTemplate.Size then
		local newSize = {}
		for i, keypoint in ipairs(baseTemplate.Size.Keypoints) do
			table.insert(newSize, NumberSequenceKeypoint.new(keypoint.Time, keypoint.Value * partScale))
		end
		emitter.Size = NumberSequence.new(newSize)
	end
end

-- ===== CREATE CLOUD FROM PART =====
function CloudSystem.createCloudFromPart(part)
	if _cloudParts[part] then
		return
	end

	local partSize = (part.Size.X + part.Size.Y + part.Size.Z) / 3
	local partBounds = part.Size / 2
	local seedValue = noise3(part.Position.X * 0.01, part.Position.Y * 0.01, part.Position.Z * 0.01)

	-- OPTIMIZED: fewer emitters, higher efficiency
	-- 10: ~15, 50: ~25, 100: ~35, 300: ~50, 500: ~55 (capped)
	local baseCount = 20
	local volumeScale = math.min(partSize / 8, 2.75)
	local targetEmitterCount = math.floor(baseCount * volumeScale)
	targetEmitterCount = math.min(targetEmitterCount, 55)

	local emitters = {}
	local attachments = {}
	local emitterData = {}

	for i = 1, 250 do
		if #emitters >= targetEmitterCount then
			break
		end

		local rand1 = noise3(i, seedValue, 0)
		local rand2 = noise3(i + 100, seedValue, 1)
		local rand3 = noise3(i + 200, seedValue, 2)

		local x = (rand1 * 2 - 1)
		local y = (rand2 * 2 - 1)
		local z = (rand3 * 2 - 1)

		local distFromCenter = math.sqrt(x * x + y * y + z * z)
		local noiseDensity = noise3(x * 2, y * 2, z * 2)
		local densityGradient = math.pow(math.max(0, 1 - (distFromCenter / 1.6)), 1.1)
		local acceptance = (densityGradient * 0.75 + 0.25) * noiseDensity

		if acceptance > 0.32 then
			local edgeRandomness = distFromCenter > 1.2 and 0.35 or 0.15
			local randJitterX = (noise3(i * 10, seedValue, 0) * 2 - 1) * edgeRandomness
			local randJitterY = (noise3(i * 10, seedValue, 1) * 2 - 1) * edgeRandomness
			local randJitterZ = (noise3(i * 10, seedValue, 2) * 2 - 1) * edgeRandomness

			local basePos = Vector3.new(
				(x + randJitterX) * partBounds.X,
				(y + randJitterY) * partBounds.Y,
				(z + randJitterZ) * partBounds.Z
			)

			local attachment = acquireAttachmentFromPool(part)
			attachment.Position = basePos

			local emitter = acquireEmitterFromPool()
			emitter.Parent = attachment

			local isCore = (distFromCenter < 0.65)
			local template = isCore and CloudConfig.EMITTER_TEMPLATES.CLOUD_CORE
				or CloudConfig.EMITTER_TEMPLATES.CLOUD_OUTER

			applyTemplate(emitter, template)
			scaleEmitterByPart(emitter, partSize, template)

			local accelMag = 0.008
			local accelAngle = math.atan2(z, x)
			emitter.Acceleration = Vector3.new(
				math.cos(accelAngle) * accelMag,
				0.008 + (noiseDensity * 0.004),
				math.sin(accelAngle) * accelMag
			)

			emitter.Enabled = true
			table.insert(emitters, emitter)
			table.insert(attachments, attachment)
			table.insert(_allEmitters, emitter)

			table.insert(emitterData, {
				emitter = emitter,
				attachment = attachment,
				basePos = basePos,
				noiseOffset = i,
				isCore = isCore,
				lastEmitPos = basePos,
			})
		end
	end

	_cloudCount += 1
	_cloudParts[part] = {
		emitters = emitters,
		attachments = attachments,
		emitterData = emitterData,
		scaleFactor = partSize,
		active = true,
		lastDistance = 0,
		seedValue = seedValue,
	}

	_activeClouds = _activeClouds + #emitters
end

-- ===== ANIMATE =====
-- The jitter is a function of floor(time * speed), so it only changes a couple of times a second:
-- recompute (and Emit) only when that step ticks over instead of running noise3 for every emitter every frame.
local CORE_STEP_SPEED, CORE_JITTER = 0.8, 2.0
local OUTER_STEP_SPEED, OUTER_JITTER = 1.2, 3.0

local function animateCloudAttachments()
	local now = _animationTime
	local coreStep = math.floor(now * CORE_STEP_SPEED)
	local outerStep = math.floor(now * OUTER_STEP_SPEED)

	for part, cloudData in pairs(_cloudParts) do
		if not part.Parent or not cloudData.active then
			continue
		end

		for _, data in ipairs(cloudData.emitterData) do
			local step = data.isCore and coreStep or outerStep
			if data.lastStep == step then
				continue
			end
			data.lastStep = step

			local jitter = data.isCore and CORE_JITTER or OUTER_JITTER
			local randX = noise3(data.noiseOffset, step, 0) * 2 - 1
			local randY = noise3(data.noiseOffset + 1, step, 1) * 2 - 1
			local randZ = noise3(data.noiseOffset + 2, step, 2) * 2 - 1

			-- cubic bias toward the cloud centre
			local newPos = data.basePos + Vector3.new(randX ^ 3 * jitter, randY ^ 3 * jitter, randZ ^ 3 * jitter)

			if newPos ~= data.lastEmitPos then
				data.attachment.Position = newPos
				if data.emitter and data.emitter.Enabled then
					data.emitter:Emit(1)
				end
				data.lastEmitPos = newPos
			end
		end
	end
end

-- ===== UPDATE LOD =====
local function updateCloudLOD(part, cloudData, cameraPos)
	local distance = (part.Position - cameraPos).Magnitude
	cloudData.lastDistance = distance

	local distConfig = CloudConfig.LOD_DISTANCES

	if distance > distConfig.FADE_END then
		if cloudData.active then
			for _, emitter in ipairs(cloudData.emitters) do
				emitter.Enabled = false
			end
			cloudData.active = false
			_activeClouds = _activeClouds - #cloudData.emitters
		end
		return
	end

	if distance > distConfig.FADE_START then
		for _, emitter in ipairs(cloudData.emitters) do
			emitter.Enabled = true
		end
		return
	end

	if not cloudData.active then
		for _, emitter in ipairs(cloudData.emitters) do
			emitter.Enabled = true
		end
		cloudData.active = true
		_activeClouds = _activeClouds + #cloudData.emitters
	end
end

function CloudSystem.updateLOD(cameraPosition)
	local now = tick()
	if now - _lastLODCheck < CloudConfig.LOD_DISTANCES.CHECK_INTERVAL then
		return
	end
	_lastLODCheck = now

	for part, cloudData in pairs(_cloudParts) do
		if part.Parent then
			updateCloudLOD(part, cloudData, cameraPosition)
		else
			for _, emitter in ipairs(cloudData.emitters) do
				releaseEmitterToPool(emitter)
				for i, e in ipairs(_allEmitters) do
					if e == emitter then
						table.remove(_allEmitters, i)
						break
					end
				end
			end
			for _, attachment in ipairs(cloudData.attachments) do
				releaseAttachmentToPool(attachment)
			end
			_cloudParts[part] = nil
			_cloudCount -= 1
			if cloudData.active then
				_activeClouds = _activeClouds - #cloudData.emitters
			end
		end
	end
end

-- ===== SHARED ANIMATION LOOP =====
local function setupHeartbeat()
	if _heartbeatConn then
		_heartbeatConn:Disconnect()
	end

	_heartbeatConn = RunService.Heartbeat:Connect(function(deltaTime)
		_animationTime = _animationTime + deltaTime
		animateCloudAttachments()
	end)
end

function CloudSystem.initialize()
	for i = 1, CloudConfig.POOLING.EMITTER_POOL_SIZE do
		local emitter = Instance.new("ParticleEmitter")
		table.insert(_emitterPool, { emitter = emitter, inUse = false })
	end

	for i = 1, CloudConfig.POOLING.EMITTER_POOL_SIZE do
		local attachment = Instance.new("Attachment")
		table.insert(_attachmentPool, { attachment = attachment, inUse = false })
	end

	setupHeartbeat()
end

function CloudSystem.destroy()
	if _heartbeatConn then
		_heartbeatConn:Disconnect()
		_heartbeatConn = nil
	end

	for part, cloudData in pairs(_cloudParts) do
		for _, emitter in ipairs(cloudData.emitters) do
			emitter:Destroy()
		end
		for _, attachment in ipairs(cloudData.attachments) do
			attachment:Destroy()
		end
	end
	for _, poolEntry in ipairs(_emitterPool) do
		poolEntry.emitter:Destroy()
	end
	for _, poolEntry in ipairs(_attachmentPool) do
		poolEntry.attachment:Destroy()
	end

	_cloudParts = {}
	_cloudCount = 0
	_emitterPool = {}
	_attachmentPool = {}
	_allEmitters = {}
	_activeClouds = 0
end

function CloudSystem.getActiveCloudCount()
	return _activeClouds
end

function CloudSystem.getTotalCloudCount()
	return _cloudCount
end

return CloudSystem
