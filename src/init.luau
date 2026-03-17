--!strict
--SimpleZone2.init

debug.setmemorycategory("DEPENDENCY :: SimplerZone")

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

local Types = require("@self/Types")
local Geometry = require("@self/Geometry")
local ZoneScheduler = require("@self/ZoneScheduler")

local worldModel = require("@self/WorldModel")

export type ShapeInstance = Types.ShapeInstance
export type Zone = Types.Zone
export type ZoneListener = Types.ZoneListener
export type TrackGroup = Types.TrackGroup
export type Shape = Types.Shape

export type BoxShape = Types.BoxShape
export type CylinderShape = Types.CylinderShape
export type SphereShape = Types.SphereShape
export type WedgeShape = Types.WedgeShape
export type GroupShape = Types.GroupShape
export type MeshShape = Types.MeshShape

type ZoneItems = Types.ZoneItems
type ZoneItem = Types.ZoneItem
type ZoneListenerData = Types.ZoneListenerData

local ShapeInstance = {} :: ShapeInstance
local Zone = {} :: Zone

local ZoneListener = ({}:: any) :: ZoneListener

local RANDOM_POINT_DIMENSION = 3
local function checkTrackGroupImmutable(group: ZoneItems)
	assert(
		table.isfrozen(group.parts)
			and table.isfrozen(group.models)
			and table.isfrozen(group.players)
			and table.isfrozen(group.attachments)
			and table.isfrozen(group.pvinstances),
		"TrackGroup members must be immutable"
	)
end

local function noyieldcall<T...>(fn: (T...) -> ...any, ...: T...)
	for _ in fn, ... do return end
end

local function MESH_isPointInShape(shape: Shape, worldCFrame: CFrame, point: vector)
	if shape.ty ~= "Mesh" then return false end

	local mesh = shape.mesh
	local shapeCFrame = worldCFrame * shape.transform

	local localPoint = shapeCFrame:PointToObjectSpace(point :: any)
	local meshCenter = Vector3.zero

	local direction = meshCenter - localPoint
	local distance = direction.Magnitude

	if distance < 0.001 then
		return true
	end

	local raycastParams = RaycastParams.new()
	raycastParams.FilterDescendantsInstances = {mesh}
	raycastParams.FilterType = Enum.RaycastFilterType.Include

	local result = worldModel:Raycast(localPoint, direction, raycastParams)

	return result == nil
end

local function MESH_isBoxInShape(shape: Shape, worldCFrame: CFrame, boxCf: CFrame, boxSize: vector)
	return MESH_isPointInShape(shape, worldCFrame, boxCf.Position :: any)
end

local function getShapeTransform(shape: Shape)
	if shape.ty == "Box" or shape.ty == "Cylinder" or shape.ty == "Mesh" or shape.ty == "Group" or shape.ty == "Wedge" then
		return shape.transform
	elseif shape.ty == "Sphere" then
		return CFrame.new(shape.center :: any)
	end
	error("exhaustive")
end

local function getWorldAABB(cf: CFrame, size: vector): (vector, vector)
	local hx, hy, hz = size.x / 2, size.y / 2, size.z / 2
	local ax = vector.create(math.abs(cf.RightVector.X), math.abs(cf.RightVector.Y), math.abs(cf.RightVector.Z))
	local ay = vector.create(math.abs(cf.UpVector.X), math.abs(cf.UpVector.Y), math.abs(cf.UpVector.Z))
	local az = vector.create(math.abs(cf.LookVector.X), math.abs(cf.LookVector.Y), math.abs(cf.LookVector.Z))
	local worldHalf = vector.create(
		ax.x * hx + ay.x * hy + az.x * hz,
		ax.y * hx + ay.y * hy + az.y * hz,
		ax.z * hx + ay.z * hy + az.z * hz
	)
	local pos: vector = cf.Position :: any
	return pos - worldHalf, pos + worldHalf
end

local function toAABB(cf: CFrame, size: vector): (CFrame, vector)
	local min, max = getWorldAABB(cf, size)
	local aabbSize = max - min
	local aabbCenter = (min + max) / 2
	return CFrame.new(aabbCenter :: any), aabbSize
end

local function pointInAABB(point: vector, boxCFrame: CFrame, boxSize: vector): boolean
	local local_point: vector = boxCFrame:PointToObjectSpace(point :: any) :: any
	local h = boxSize / 2
	return math.abs(local_point.x) <= h.x
		and math.abs(local_point.y) <= h.y
		and math.abs(local_point.z) <= h.z
end

local function obbInAABB(obbCFrame: CFrame, obbSize: vector, aabbCFrame: CFrame, aabbSize: vector): boolean
	local min, max = getWorldAABB(obbCFrame, obbSize)
	local obbAABBCenter = (min + max) / 2
	local obbAABBSize = max - min
	local aabbPos: vector = aabbCFrame.Position :: any
	local ah = aabbSize / 2
	local oh = obbAABBSize / 2
	return math.abs(obbAABBCenter.x - aabbPos.x) <= ah.x + oh.x
		and math.abs(obbAABBCenter.y - aabbPos.y) <= ah.y + oh.y
		and math.abs(obbAABBCenter.z - aabbPos.z) <= ah.z + oh.z
end

local function flattenShapeToBoxes(shape: Shape, worldCFrame: CFrame, shapeInst: ShapeInstance): {Geometry.Box}
	local boxes: {Geometry.Box} = {}
	if shape.ty == "Box" then
		local cf, size = toAABB(worldCFrame * shape.transform, shape.size * shapeInst.scale)
		table.insert(boxes, { cframe = cf, size = size, data = {shape = shape, cframe = worldCFrame * shape.transform, shapeInst = shapeInst} })
	elseif shape.ty == "Sphere" then
		local cf = worldCFrame * CFrame.new(shape.center :: any)
		local size = vector.create(shape.radius * 2, shape.radius * 2, shape.radius * 2) * shapeInst.scale
		table.insert(boxes, { cframe = cf, size = size, data = {shape = shape, cframe = cf, shapeInst = shapeInst} })
	elseif shape.ty == "Cylinder" then
		local cf, size = toAABB(worldCFrame * shape.transform, shape.size * shapeInst.scale)
		table.insert(boxes, { cframe = cf, size = size, data = {shape = shape, cframe = worldCFrame * shape.transform, shapeInst = shapeInst} })
	elseif shape.ty == "Wedge" then
		local cf, size = toAABB(worldCFrame * shape.transform, shape.size * shapeInst.scale)
		table.insert(boxes, { cframe = cf, size = size, data = {shape = shape, cframe = worldCFrame * shape.transform, shapeInst = shapeInst} })
	elseif shape.ty == "Mesh" then
		local cf, size = toAABB(worldCFrame * shape.transform, shape.size * shapeInst.scale)
		table.insert(boxes, { cframe = cf, size = size, data = {shape = shape, cframe = worldCFrame * shape.transform, shapeInst = shapeInst} })
	elseif shape.ty == "Group" then
		local groupWorldCFrame = worldCFrame * shape.transform
		for _, childShape: Shape in shape.shapes do
			local childWorldCFrame = groupWorldCFrame * getShapeTransform(childShape)
			local childBoxes = flattenShapeToBoxes(childShape, childWorldCFrame, shapeInst)
			for _, box in childBoxes do
				table.insert(boxes, box)
			end
		end
	end
	return boxes
end

local function isBoxInShape(partCFrame: CFrame, partSize: vector, shape: Shape, worldCFrame: CFrame): boolean
	if shape.ty == "Box" then
		return Geometry.doBoxesIntersect(partCFrame, partSize, worldCFrame * shape.transform, shape.size)
	elseif shape.ty == "Sphere" then
		local sphereCenter = (worldCFrame * CFrame.new(shape.center :: any)).Position
		return Geometry.doesBoxIntersectSphere(sphereCenter :: any, shape.radius, partCFrame, partSize)
	elseif shape.ty == "Cylinder" then
		return Geometry.BoxCylinderIntersection.queryUsingGeoms(
			Geometry.BoxCylinderIntersection.getBoxGeometry(partSize),
			Geometry.BoxCylinderIntersection.getCylinderGeometryNoPart(
				worldCFrame * shape.transform,
				shape.size,
				partCFrame
			)
		)
	elseif shape.ty == "Wedge" then
		return Geometry.doesBoxIntersectWedge(partCFrame, partSize, worldCFrame * shape.transform, shape.size)
	elseif shape.ty == "Group" then
		local groupWorldCFrame = worldCFrame * shape.transform
		for _, childShape in shape.shapes do
			if isBoxInShape(partCFrame, partSize, childShape, groupWorldCFrame) then
				return true
			end
		end
		return false
	elseif shape.ty == "Mesh" then
		return MESH_isBoxInShape(shape, worldCFrame, partCFrame, partSize)
	end

	return false
end

local function isPointInShapeVolume(point: vector, shape: Shape, worldCFrame: CFrame, shapeInst: ShapeInstance): boolean
	if shape.ty == "Box" then
		local cf = worldCFrame * shape.transform
		local size = shape.size
		
		local halfSize = size / 2
		local localPoint = cf:PointToObjectSpace(point :: any)

		local withinX = math.abs(localPoint.X) <= halfSize.x
		local withinY = math.abs(localPoint.Y) <= halfSize.y
		local withinZ = math.abs(localPoint.Z) <= halfSize.z

		return withinX and withinY and withinZ
	elseif shape.ty == "Sphere" then
		local sphereCenter = (worldCFrame * CFrame.new(shape.center :: any)).Position
		local distance = vector.magnitude(point - (sphereCenter :: any))
		return distance <= shape.radius
	elseif shape.ty == "Cylinder" then
		local cylinderCFrame = worldCFrame * shape.transform
		local cylinderCenter = cylinderCFrame.Position
		local toPoint = point - (cylinderCenter :: any)
		local axisUnit = cylinderCFrame.XVector
		local projectionLength = vector.dot(toPoint, axisUnit :: any)
		local axisLength = shape.size.x

		if math.abs(projectionLength) > axisLength / 2 then
			return false
		end

		local radialVector = toPoint - (axisUnit :: any) * projectionLength
		return radialVector.Magnitude <= shape.radius
	elseif shape.ty == "Wedge" then
		local size = shape.size
		local cf = worldCFrame * shape.transform
		local pos = cf.Position

		local s2 = size / 2

		local xvec = cf.XVector.Unit * s2.x
		local yvec = cf.YVector.Unit * s2.y
		local zvec = cf.ZVector.Unit * s2.z

		-- Backwards, right, up
		local a = pos + xvec + zvec + yvec
		-- Backwards, right, down
		local b = pos + xvec + zvec - yvec
		-- Forwards, right, down
		local c = pos + xvec - zvec - yvec

		local point = cf:PointToWorldSpace(
			cf:PointToObjectSpace(point :: any) :: any * vector.create(0, 1, 1) + vector.create(size.x/2, 0, 0)
		) :: any

		return Geometry.isPointInTri(point, a :: any, b :: any, c :: any)
	elseif shape.ty == "Group" then
		local groupWorldCFrame = worldCFrame * shape.transform
		for _, childShape in shape.shapes do
			if childShape.ty ~= "Group" then
				local boxes = flattenShapeToBoxes(childShape, groupWorldCFrame, shapeInst)
				if #boxes > 0 then
					local box = boxes[1]
					if not pointInAABB(point, box.cframe, box.size) then
						continue
					end
				end
			else
				local boxes = flattenShapeToBoxes(childShape, groupWorldCFrame, shapeInst)
				local cf, size = Geometry.getBoundingBoxFromBoxes(boxes)
				if not pointInAABB(point, cf, size) then
					continue
				end
			end

			if isPointInShapeVolume(point, childShape, groupWorldCFrame, shapeInst) then
				return true
			end
		end
		return false
	elseif shape.ty == "Mesh" then
		return MESH_isPointInShape(shape, worldCFrame, point)
	end

	return false
end

local function checkPointInGroup(point: vector, bvh): ShapeInstance?
	if not bvh then return nil end
	
	local foundShape = nil :: ShapeInstance?
	Geometry.Bvh.traverseBVH(bvh, function(node, stop)
		if not pointInAABB(point, node.cframe, node.size) then
			return false
		end

		if not node.left and not node.right then
			local leaf = node.data
			if leaf and isPointInShapeVolume(point, leaf.shape, leaf.cframe, leaf.shapeInst) then
				foundShape = leaf.shapeInst
				stop()
			end
			return false
		end

		return true
	end)

	return foundShape
end

local function checkBoxInGroup(cframe: CFrame, size: vector, bvh): ShapeInstance?
	if not bvh then return nil end
	
	local foundShape = nil :: ShapeInstance?
	Geometry.Bvh.traverseBVH(bvh, function(node, stop)
		if not obbInAABB(cframe, size, node.cframe, node.size) then
			return false
		end

		if not node.left and not node.right then
			local leaf = node.data
			if leaf and isBoxInShape(cframe, size, leaf.shape, leaf.cframe) then
				foundShape = leaf.shapeInst
				stop()
			end
			return false
		end

		return true
	end)

	return foundShape
end

local function checkPartInGroup(part: BasePart, bvh): ShapeInstance?
	return checkBoxInGroup(part.CFrame, part.Size :: any, bvh)
end

function ShapeInstance:toParts(overrideCFrame: CFrame?)
	local shape = self.shape

	local function toPart(shape: Shape, overrideCFrame: CFrame?): {BasePart}
		local worldCFrame = overrideCFrame or self.cframe
		if shape.ty == "Box" then
			local part = Instance.new("Part")
			part.Anchored = true
			part.Shape = Enum.PartType.Block
			part.Size = shape.size :: any
			part.CFrame = worldCFrame * shape.transform
			part.CanCollide = false
			return {part}
		elseif shape.ty == "Sphere" then
			local part = Instance.new("Part")
			part.Anchored = true
			part.Shape = Enum.PartType.Ball
			local diameter = shape.radius * 2
			part.Size = Vector3.new(diameter, diameter, diameter)
			part.CFrame = worldCFrame * CFrame.new(shape.center :: any)
			part.CanCollide = false
			return {part}
		elseif shape.ty == "Cylinder" then
			local part = Instance.new("Part")
			part.Anchored = true
			part.Shape = Enum.PartType.Cylinder
			part.Size = shape.size :: any
			part.CanCollide = false
			part.CFrame = worldCFrame * shape.transform
			return {part}
		elseif shape.ty == "Wedge" then
			local part = Instance.new("WedgePart")
			part.Size = shape.size :: any
			part.Anchored = true
			part.CanCollide = false
			part.CFrame = worldCFrame * shape.transform
			return {part}
		elseif shape.ty == "Mesh" then
			local part = Instance.fromExisting(shape.mesh)
			part.Anchored = true
			part.Size = shape.size :: any
			part.CanCollide = false
			part.CFrame = worldCFrame * shape.transform
			return {part}
		elseif shape.ty == "Group" then
			local parts = {}
			local groupWorldCFrame = worldCFrame * shape.transform
			for _, childShape: Shape in shape.shapes do
				local childWorldCFrame = groupWorldCFrame * getShapeTransform(childShape)
				local childParts = toPart(childShape, childWorldCFrame)
				for _, v in childParts do
					table.insert(parts, v)
				end
			end
			return parts
		end
		return {}
	end

	return toPart(shape, overrideCFrame)
end

local function getScale(shape: Types.Shape, targetSize: vector): vector
	if shape.ty == "Sphere" then
		local d = shape.radius * 2
		local scale = targetSize.x / d
		return vector.create(scale, scale, scale)
	elseif shape.ty == "Box" or shape.ty == "Wedge" or shape.ty == "Mesh" or shape.ty == "Cylinder" then
		return vector.create(
			targetSize.x / shape.size.x,
			targetSize.y / shape.size.y,
			targetSize.z / shape.size.z
		)
	elseif shape.ty == "Group" then
		local min = vector.create(math.huge, math.huge, math.huge)
		local max = vector.create(-math.huge, -math.huge, -math.huge)
		for _, child in shape.shapes do
			local childSize
			if child.ty == "Sphere" then
				local d = child.radius * 2
				childSize = vector.create(d, d, d)
			elseif child.ty == "Group" then
				local childScale = getScale(child, vector.create(1, 1, 1))
				childSize = vector.create(1 / childScale.x, 1 / childScale.y, 1 / childScale.z)
			else
				childSize = child.size
			end
			local origin: vector = getShapeTransform(child).Position :: any
			local half = childSize / 2
			min = vector.create(
				math.min(min.x, origin.x - half.x),
				math.min(min.y, origin.y - half.y),
				math.min(min.z, origin.z - half.z)
			)
			max = vector.create(
				math.max(max.x, origin.x + half.x),
				math.max(max.y, origin.y + half.y),
				math.max(max.z, origin.z + half.z)
			)
		end
		local baseSize = max - min
		return vector.create(
			targetSize.x / baseSize.x,
			targetSize.y / baseSize.y,
			targetSize.z / baseSize.z
		)
	end
	error(`Unhandled shape type: {shape.ty}`)
end

function ShapeInstance:syncWithPart(part)
	self.cframe = part.CFrame
	self.scale = getScale(self.shape, part.ExtentsSize :: any)

	local function onCFrameChanged()
		self.cframe = part.CFrame
		for _, zone in self.zones do
			zone.bvhDirty = true
			ZoneScheduler.markZoneDirtyForListeners(zone)
		end
	end
	
	local function onSizeChanged()
		self.scale = getScale(self.shape, part.ExtentsSize :: any)
		for _, zone in self.zones do
			zone.bvhDirty = true
			ZoneScheduler.markZoneDirtyForListeners(zone)
		end
	end

	local cframeChanged = part:GetPropertyChangedSignal("CFrame"):Connect(onCFrameChanged)
	local sizeChanged = part:GetPropertyChangedSignal("Size"):Connect(onSizeChanged)

	return function()
		cframeChanged:Disconnect()
		sizeChanged:Disconnect()
	end
end

function ShapeInstance:syncWithAttachment(attachment)
	self.cframe = attachment.WorldCFrame

	local cframeChanged = attachment:GetPropertyChangedSignal("WorldCFrame"):Connect(function()
		self.cframe = attachment.WorldCFrame
		for _, zone in self.zones do
			zone.bvhDirty = true
			ZoneScheduler.markZoneDirtyForListeners(zone)
		end
	end)

	return function()
		cframeChanged:Disconnect()
	end
end

function ShapeInstance:attach(zone)
	table.insert(self.zones, zone)
	table.insert(zone.shapes, self)
	zone.bvhDirty = true
end

function ShapeInstance:detach(zone)
	local shapes = zone.shapes
	local index = table.find(shapes, self)
	if index then
		table.remove(shapes, index)
	end
	local index = table.find(self.zones, zone)
	if index then
		table.remove(self.zones, index)
	end
	zone.bvhDirty = true
end

function ShapeInstance:detachAll()
	for _, zone in self.zones do
		zone.bvhDirty = true
	end
	table.clear(self.zones)
end

function Zone:rebuild()
	local boxes: {Geometry.Box} = {}

	for _, shapeInstance in self.shapes do
		local shapeBoxes = flattenShapeToBoxes(shapeInstance.shape, shapeInstance.cframe, shapeInstance)
		for _, box in shapeBoxes do
			table.insert(boxes, box)
		end
	end
	
	--self.boxes = boxes
	--self.bvh = Geometry.Bvh.createBVH(boxes)
	local updated, newBvh = Geometry.Bvh.updateBVH(self.bvh, self.boxes, boxes, self.bvhRestructureWeight)
	if updated then
		self.bvh = newBvh
	end
	self.boxes = boxes
	self.bvhDirty = false
end

function Zone:rebuildIfDirty()
	if not self.bvhDirty then return end
	self:rebuild()
end

local function clampBiasToShape(shape: Shape, worldCFrame: CFrame, biasWorld: vector): vector
	if shape.ty == "Box" then
		local cframe = worldCFrame * shape.transform
		local size = shape.size
		local local_ = cframe:PointToObjectSpace(biasWorld :: any)
		local clamped = vector.create(
			math.clamp(local_.X, -size.x/2, size.x/2),
			math.clamp(local_.Y, -size.y/2, size.y/2),
			math.clamp(local_.Z, -size.z/2, size.z/2)
		)
		return cframe:PointToWorldSpace(clamped :: any) :: any
	elseif shape.ty == "Wedge" then
		local cframe = worldCFrame * shape.transform
		local size = shape.size
		local sx, sy, sz = size.x, size.y, size.z
		local local_ = cframe:PointToObjectSpace(biasWorld :: any)
		-- clamp X and Z first
		local cx = math.clamp(local_.X, -sx/2, sx/2)
		local cz = math.clamp(local_.Z, -sz/2, sz/2)
		-- max Y at this Z (slope rises toward +z)
		local maxY = sy * (0.5 + cz / sz)
		local cy = math.clamp(local_.Y, -sy/2, maxY - sy/2)
		return cframe:PointToWorldSpace(Vector3.new(cx, cy, cz)) :: any
	elseif shape.ty == "Sphere" then
		local center = (worldCFrame * CFrame.new(shape.center :: any)).Position
		local offset = (biasWorld :: any) - center
		local dist = vector.magnitude(offset)
		if dist > shape.radius then
			return center + vector.normalize(offset) * shape.radius :: any
		end
		return biasWorld
	elseif shape.ty == "Cylinder" then
		local localCF = worldCFrame * shape.transform
		local height = vector.magnitude(shape.axis)
		local local_ = localCF:PointToObjectSpace(biasWorld :: any)
		-- clamp along X (height axis), then clamp radially in Y/Z
		local cx = math.clamp(local_.X, -height/2, height/2)
		local yz = Vector2.new(local_.Y, local_.Z)
		local yzLen = yz.Magnitude
		local cy, cz
		if yzLen > shape.radius then
			local scale = shape.radius / yzLen
			cy = local_.Y * scale
			cz = local_.Z * scale
		else
			cy = local_.Y
			cz = local_.Z
		end
		return localCF:PointToWorldSpace(Vector3.new(cx, cy, cz)) :: any
	elseif shape.ty == "Group" then
		-- clamp to the nearest shape in the group
		local best, bestDist = biasWorld, math.huge
		for _, subShape in shape.shapes do
			local clamped = clampBiasToShape(subShape, worldCFrame * shape.transform, biasWorld)
			local dist = vector.magnitude((clamped :: any) - (biasWorld :: any))
			if dist < bestDist then
				best, bestDist = clamped, dist
			end
		end
		return best
	end

	return biasWorld
end

local function getRandomPointInShape(shape: Shape, worldCFrame: CFrame)
	if shape.ty == "Box" then
		local cframe, size = worldCFrame * shape.transform, shape.size
		local randomX = math.random() * size.x - size.x / 2
		local randomY = math.random() * size.y - size.y / 2
		local randomZ = math.random() * size.z - size.z / 2
		local randomPoint = cframe:PointToWorldSpace(vector.create(randomX, randomY, randomZ) :: any)
		return randomPoint :: any
	elseif shape.ty == "Wedge" then
		local rand = Random.new()
		local cframe = worldCFrame * shape.transform
		local size = shape.size
		local sx, sy, sz = size.x, size.y, size.z

		local u = rand:NextNumber()
		local t = math.sqrt(u)
		local z = sz * (t - 0.5)
		local maxY = sy * (0.5 + z / sz)

		local x = (rand:NextNumber() - 0.5) * sx
		local y = -sy / 2 + rand:NextNumber() * maxY
		return cframe:PointToWorldSpace(Vector3.new(x, y, z))
	elseif shape.ty == "Sphere" then
		local rand = Random.new()
		local dir = rand:NextUnitVector()
		local r = rand:NextNumber()^(1/3)
		local sphereCenter = (worldCFrame * CFrame.new(shape.center :: any)).Position
		return (sphereCenter :: any) + dir::any * r * shape.radius
	elseif shape.ty == "Cylinder" then
		local rand = Random.new()
		local radius = shape.radius
		local height = vector.magnitude(shape.axis)
		local localCF = worldCFrame * shape.transform

		local theta = rand:NextNumber() * math.pi * 2
		local r = radius * math.sqrt(rand:NextNumber())
		local y = r * math.cos(theta)
		local z = r * math.sin(theta)

		local x = (rand:NextNumber() - 0.5) * height
		local localPoint = Vector3.new(x, y, z)
		return localCF:PointToWorldSpace(localPoint)
	elseif shape.ty == "Group" then
		local shapes = shape.shapes
		local randomShape = shapes[math.random(1, #shapes)]
		return getRandomPointInShape(randomShape, worldCFrame * shape.transform)
	end
	return vector.zero
end

function Zone:getRandomPoint(bias)
	local shapes = self.shapes
	local shapeInstance = shapes[math.random(1, #shapes)]
	local shape = shapeInstance.shape

	local point = getRandomPointInShape(shape, shapeInstance.cframe)

	if bias then
		local clamped = clampBiasToShape(shape, shapeInstance.cframe, bias)
		local blend = math.random() ^ 2
		point = point + (clamped - point) * blend
	end
	
	return point
end

function Zone:getShapeWithPoint(point)
	self:rebuildIfDirty()
	return checkPointInGroup(point, self.bvh)
end

function Zone:getShapeWithBox(cframe, size)
	self:rebuildIfDirty()
	return checkBoxInGroup(cframe, size, self.bvh)
end

function Zone:isPointInZone(point)
	return self:getShapeWithPoint(point) ~= nil
end

function Zone:isBoxInZone(cframe, size)
	return self:getShapeWithBox(cframe, size) ~= nil
end

local function getPartsFromModel(model: Model): {BasePart}
	return model:QueryDescendants("BasePart") :: any
end

local function getAttachmentWorldPosition(attachment: Attachment): vector
	local parent = attachment.Parent
	if parent and parent:IsA("BasePart") then
		return (parent.CFrame * attachment.CFrame).Position :: any
	end
	return attachment.WorldPosition :: any
end

local function getPVInstanceBounds(pvi: PVInstance): (CFrame, vector)
	if pvi:IsA("Model") then
		local cf, size = pvi:GetBoundingBox()
		return cf, size :: any
	elseif pvi:IsA("BasePart") then
		return pvi.CFrame, pvi.Size :: any
	else
		return pvi:GetPivot(), vector.zero
	end
end

local function ZoneListener_setupPartTracking(self: ZoneListener, part: BasePart, owner: Model | Player | nil)
	local data = self.data
	local precision = self.precision or "Part"

	if data.partConnections[part] then return end

	if owner then
		if typeof(owner) == "Instance" and owner:IsA("Model") then
			data.partToModel[part] = owner :: Model
		elseif typeof(owner) == "Instance" and owner:IsA("Player") then
			data.partToPlayer[part] = owner :: Player
		end
	end

	if precision == "BoundingBox" and owner then
		return
	end
	
	local isInside = false
	for _, z in self.zones do
		z:rebuildIfDirty()
		if checkPartInGroup(part, z.bvh) then
			isInside = true
			break
		end
	end

	if isInside then
		table.insert(self.itemsInside.parts, part)
		data.partsSet[part] = true

		if owner then
			if typeof(owner) == "Instance" and owner:IsA("Model") then
				local model = owner :: Model
				if not data.modelPartsInside[model] then
					data.modelPartsInside[model] = {}
					table.insert(self.itemsInside.models, model)
				end
				table.insert(data.modelPartsInside[model], part)
			elseif typeof(owner) == "Instance" and owner:IsA("Player") then
				local player = owner :: Player
				if not data.playerPartsInside[player] then
					data.playerPartsInside[player] = {}
					table.insert(self.itemsInside.players, player)
				end
				table.insert(data.playerPartsInside[player], part)
			end
		end
	end

	if owner then return end

	local partConnections = {}
	if self.queryShape == "Point" then
		table.insert(partConnections, part:GetPropertyChangedSignal("Position"):Connect(function()
			for _, zone in self.zones do
				ZoneScheduler.markPartDirty(part, self, owner, zone)
			end
		end))
	else
		table.insert(partConnections, part:GetPropertyChangedSignal("CFrame"):Connect(function()
			for _, zone in self.zones do
				ZoneScheduler.markPartDirty(part, self, owner, zone)
			end
		end))
	end
	table.insert(partConnections, part:GetPropertyChangedSignal("Size"):Connect(function()
		for _, zone in self.zones do
			ZoneScheduler.markPartDirty(part, self, owner, zone)
		end
	end))
	table.insert(partConnections, part.AncestryChanged:Connect(function()
		if not part:IsDescendantOf(game) then
			if data.partsSet[part] then
				local index = table.find(self.itemsInside.parts, part)
				if index then table.remove(self.itemsInside.parts, index) end
				data.partsSet[part] = nil
				
				local item = {part = part}
				for _, observer in data.exitObservers do
					noyieldcall(observer, item)
				end
			end
			if data.partConnections[part] then
				for _, conn in data.partConnections[part] do conn:Disconnect() end
				data.partConnections[part] = nil
			end
		end
	end))

	data.partConnections[part] = partConnections
end

local function ZoneListener_setupAttachmentTracking(self: ZoneListener, attachment: Attachment)
	local data = self.data

	if data.attachmentConnections[attachment] then return end

	local isInside = false
	for _, z in self.zones do
		z:rebuildIfDirty()
		local pos = getAttachmentWorldPosition(attachment)
		if checkPointInGroup(pos, z.bvh) then
			isInside = true
			break
		end
	end

	if isInside then
		table.insert(self.itemsInside.attachments, attachment)
		data.attachmentsSet[attachment] = true
	end

	local conns = {}

	local parent = attachment.Parent
	if parent and parent:IsA("BasePart") then
		table.insert(conns, parent:GetPropertyChangedSignal("CFrame"):Connect(function()
			for _, zone in self.zones do
				ZoneScheduler.markAttachmentDirty(attachment, self, zone)
			end
		end))
	else
		table.insert(conns, attachment:GetPropertyChangedSignal("WorldPosition"):Connect(function()
			for _, zone in self.zones do
				ZoneScheduler.markAttachmentDirty(attachment, self, zone)
			end
		end))
	end
	table.insert(conns, attachment:GetPropertyChangedSignal("CFrame"):Connect(function()
		for _, zone in self.zones do
			ZoneScheduler.markAttachmentDirty(attachment, self, zone)
		end
	end))
	table.insert(conns, attachment.AncestryChanged:Connect(function()
		if not attachment:IsDescendantOf(game) then
			if data.attachmentsSet[attachment] then
				local index = table.find(self.itemsInside.attachments, attachment)
				if index then table.remove(self.itemsInside.attachments, index) end
				data.attachmentsSet[attachment] = nil
				
				local item = {attachment = attachment}
				for _, observer in data.exitObservers do
					noyieldcall(observer, item)
				end
			end
			if data.attachmentConnections[attachment] then
				for _, conn in data.attachmentConnections[attachment] do conn:Disconnect() end
				data.attachmentConnections[attachment] = nil
			end
		end
	end))

	data.attachmentConnections[attachment] = conns
end

local function ZoneListener_setupPVInstanceTracking(self: ZoneListener, pvi: PVInstance)
	local data = self.data
	local queryShape = self.queryShape or "Box"

	if data.pvinstanceConnections[pvi] then return end

	local isInside = false
	for _, z in self.zones do
		z:rebuildIfDirty()

		local inside
		if queryShape == "Point" then
			local pivot = pvi:GetPivot()
			inside = z:isPointInZone(pivot.Position :: any)
		else
			local cf, size = getPVInstanceBounds(pvi)
			inside = z:isBoxInZone(cf, size)
		end

		if inside then
			isInside = true
			break
		end
	end
	
	if isInside then
		table.insert(self.itemsInside.pvinstances, pvi)
		data.pvinstancesSet[pvi] = true
	end

	for _, zone in self.zones do
		ZoneScheduler.trackPVInstance(pvi, self, zone)
	end

	local conns = {}
	table.insert(conns, pvi.AncestryChanged:Connect(function()
		if not pvi:IsDescendantOf(game) then
			ZoneScheduler.untrackPVInstance(pvi, self)

			if data.pvinstancesSet[pvi] then
				local index = table.find(self.itemsInside.pvinstances, pvi)
				if index then table.remove(self.itemsInside.pvinstances, index) end
				data.pvinstancesSet[pvi] = nil
				
				local item = {pvinstance = pvi}
				for _, observer in data.exitObservers do
					noyieldcall(observer, item)
				end
			end
			if data.pvinstanceConnections[pvi] then
				for _, conn in data.pvinstanceConnections[pvi] do conn:Disconnect() end
				data.pvinstanceConnections[pvi] = nil
			end
		end
	end))

	data.pvinstanceConnections[pvi] = conns
end

local function ZoneListener_setupModelTracking(self: ZoneListener, model: Model)
	local data = self.data
	local precision = self.precision or "Part"
	local queryShape = self.queryShape or "Box"

	if data.modelConnections[model] then return end

	if precision == "Part" then
		for _, part in getPartsFromModel(model) do
			ZoneListener_setupPartTracking(self, part, model)
		end
	else
		for _, z in self.zones do
			z:rebuildIfDirty()

			local isInside
			if queryShape == "Point" then
				local pivot = model:GetPivot().Position
				isInside = z:isPointInZone(pivot :: any)
			else
				local cf, size = model:GetBoundingBox()
				isInside = z:isBoxInZone(cf, size :: any)
			end

			if isInside then
				data.modelPartsInside[model] = {}
				table.insert(self.itemsInside.models, model)
				break
			end
		end
	end

	for _, zone in self.zones do
		ZoneScheduler.trackModel(model, self, zone)
	end

	local conns = {}

	if precision == "Part" then
		table.insert(conns, model.DescendantAdded:Connect(function(descendant)
			if descendant:IsA("BasePart") then
				ZoneListener_setupPartTracking(self, descendant, model)
			end
		end))
	end
	table.insert(conns, model.AncestryChanged:Connect(function()
		if not model:IsDescendantOf(game) then
			ZoneScheduler.untrackModel(model, self)

			if data.modelConnections[model] then
				for _, conn in data.modelConnections[model] do conn:Disconnect() end
				data.modelConnections[model] = nil
			end

			if data.modelPartsInside[model] then
				if precision == "Part" then
					for _, part in data.modelPartsInside[model] do
						local index = table.find(self.itemsInside.parts, part)
						if index then table.remove(self.itemsInside.parts, index) end
						data.partsSet[part] = nil
					end
				end

				data.modelPartsInside[model] = nil
				local modelIndex = table.find(self.itemsInside.models, model)
				if modelIndex then table.remove(self.itemsInside.models, modelIndex) end
				local modelPlayer = Players:GetPlayerFromCharacter(model)
				local item = {model = model, player = modelPlayer}
				for _, observer in data.exitObservers do
					noyieldcall(observer, item)
				end
			end
		end
	end))

	data.modelConnections[model] = conns
end

local function ZoneListener_setupPlayerTracking(self: ZoneListener, player: Player)
	local data = self.data
	local precision = self.precision or "Part"
	local queryShape = self.queryShape or "Box"

	if data.playerConnections[player] then return end

	local function setupCharacter(character: Model)
		if precision == "Part" then
			for _, part in getPartsFromModel(character) do
				ZoneListener_setupPartTracking(self, part, player)
			end
			character.DescendantAdded:Connect(function(descendant)
				if descendant:IsA("BasePart") then
					ZoneListener_setupPartTracking(self, descendant, player)
				end
			end)
		else
			for _, z in self.zones do
				z:rebuildIfDirty()

				local isInside
				if queryShape == "Point" then
					local pivot = character:GetPivot().Position
					isInside = z:isPointInZone(pivot :: any)
				else
					local cf, size = character:GetBoundingBox()
					isInside = z:isBoxInZone(cf, size :: any)
				end

				if isInside then
					data.playerPartsInside[player] = {}
					table.insert(self.itemsInside.players, player)
					break
				end
			end
		end
	end

	for _, zone in self.zones do
		ZoneScheduler.trackPlayer(player, self, zone)
	end

	local conns = {}

	table.insert(conns, player.CharacterAdded:Connect(function(character)
		setupCharacter(character)
	end))
	table.insert(conns, player.CharacterRemoving:Connect(function()
		if data.playerPartsInside[player] then
			if precision == "Part" then
				for _, part in data.playerPartsInside[player] do
					local index = table.find(self.itemsInside.parts, part)
					if index then table.remove(self.itemsInside.parts, index) end
					data.partsSet[part] = nil
				end
			end

			data.playerPartsInside[player] = nil
			local playerIndex = table.find(self.itemsInside.players, player)
			if playerIndex then table.remove(self.itemsInside.players, playerIndex) end
			local item = {player = player, model = player.Character}
			for _, observer in data.exitObservers do
				noyieldcall(observer, item)
			end
		end
	end))

	if player.Character then
		setupCharacter(player.Character)
	end

	data.playerConnections[player] = conns
end

local function ZoneListener_cleanupPartTracking(self: ZoneListener, part: BasePart)
	local data = self.data

	if data.partConnections[part] then
		for _, conn in data.partConnections[part] do conn:Disconnect() end
		data.partConnections[part] = nil
	end

	if data.partsSet[part] then
		local index = table.find(self.itemsInside.parts, part)
		if index then table.remove(self.itemsInside.parts, index) end
		data.partsSet[part] = nil
		
		local item = {part = part}
		for _, observer in data.exitObservers do
			noyieldcall(observer, item)
		end
	end

	data.partToModel[part] = nil
	data.partToPlayer[part] = nil
end

local function ZoneListener_cleanupAttachmentTracking(self: ZoneListener, attachment: Attachment)
	local data = self.data

	if data.attachmentConnections[attachment] then
		for _, conn in data.attachmentConnections[attachment] do conn:Disconnect() end
		data.attachmentConnections[attachment] = nil
	end

	if data.attachmentsSet[attachment] then
		local index = table.find(self.itemsInside.attachments, attachment)
		if index then table.remove(self.itemsInside.attachments, index) end
		data.attachmentsSet[attachment] = nil
		
		local item = {attachment = attachment}
		for _, observer in data.exitObservers do
			noyieldcall(observer, item)
		end
	end
end

local function ZoneListener_cleanupPVInstanceTracking(self: ZoneListener, pvi: PVInstance)
	local data = self.data

	if data.pvinstanceConnections[pvi] then
		ZoneScheduler.untrackPVInstance(pvi, self)
		for _, conn in data.pvinstanceConnections[pvi] do conn:Disconnect() end
		data.pvinstanceConnections[pvi] = nil
	end

	if data.pvinstancesSet[pvi] then
		local index = table.find(self.itemsInside.pvinstances, pvi)
		if index then table.remove(self.itemsInside.pvinstances, index) end
		data.pvinstancesSet[pvi] = nil
		
		local item = {pvinstance = pvi}
		for _, observer in data.exitObservers do
			noyieldcall(observer, item)
		end
	end
end

local function ZoneListener_cleanupModelTracking(self: ZoneListener, model: Model)
	local data = self.data
	local precision = self.precision or "Part"

	if data.modelConnections[model] then
		ZoneScheduler.untrackModel(model, self)
		for _, conn in data.modelConnections[model] do conn:Disconnect() end
		data.modelConnections[model] = nil
	end

	if data.modelPartsInside[model] then
		if precision == "Part" then
			for _, part in data.modelPartsInside[model] do
				local index = table.find(self.itemsInside.parts, part)
				if index then table.remove(self.itemsInside.parts, index) end
				data.partsSet[part] = nil
			end
		end

		data.modelPartsInside[model] = nil
		local modelIndex = table.find(self.itemsInside.models, model)
		if modelIndex then table.remove(self.itemsInside.models, modelIndex) end

		local modelPlayer = Players:GetPlayerFromCharacter(model)
		local item = {model = model, player = modelPlayer}
		for _, observer in data.exitObservers do
			noyieldcall(observer, item)
		end
	end
end

local function ZoneListener_cleanupPlayerTracking(self: ZoneListener, player: Player)
	local data = self.data
	local precision = self.precision or "Part"

	if data.playerConnections[player] then
		ZoneScheduler.untrackPlayer(player, self)
		for _, conn in data.playerConnections[player] do conn:Disconnect() end
		data.playerConnections[player] = nil
	end

	if data.playerPartsInside[player] then
		if precision == "Part" then
			for _, part in data.playerPartsInside[player] do
				local index = table.find(self.itemsInside.parts, part)
				if index then table.remove(self.itemsInside.parts, index) end
				data.partsSet[part] = nil
			end
		end

		data.playerPartsInside[player] = nil
		local playerIndex = table.find(self.itemsInside.players, player)
		if playerIndex then table.remove(self.itemsInside.players, playerIndex) end
		
		local item = {player = player, model = player.Character}
		for _, observer in data.exitObservers do
			noyieldcall(observer, item)
		end
	end
end

local function ZoneListener_cleanupAllTracking(self: ZoneListener)
	local data = self.data

	ZoneScheduler.unregisterListener(self)

	for part, partConnections in data.partConnections do
		for _, conn in partConnections do conn:Disconnect() end
	end
	table.clear(data.partConnections)

	for attachment, conns in data.attachmentConnections do
		for _, conn in conns do conn:Disconnect() end
	end
	table.clear(data.attachmentConnections)

	for pvi, conns in data.pvinstanceConnections do
		ZoneScheduler.untrackPVInstance(pvi, self)
		for _, conn in conns do conn:Disconnect() end
	end
	table.clear(data.pvinstanceConnections)

	for model, conns in data.modelConnections do
		ZoneScheduler.untrackModel(model, self)
		for _, conn in conns do conn:Disconnect() end
	end
	table.clear(data.modelConnections)

	for player, conns in data.playerConnections do
		ZoneScheduler.untrackPlayer(player, self)
		for _, conn in conns do conn:Disconnect() end
	end
	table.clear(data.playerConnections)

	table.clear(self.itemsInside.parts)
	table.clear(self.itemsInside.attachments)
	table.clear(self.itemsInside.pvinstances)
	table.clear(self.itemsInside.models)
	table.clear(self.itemsInside.players)
	table.clear(data.partsSet)
	table.clear(data.attachmentsSet)
	table.clear(data.pvinstancesSet)
	table.clear(data.partToModel)
	table.clear(data.partToPlayer)
	table.clear(data.modelPartsInside)
	table.clear(data.playerPartsInside)
end

local function ZoneListener_incrementalUpdate(self: ZoneListener, oldImmutable, newImmutable)
	-- Parts
	for _, part in newImmutable.parts do
		if not table.find(oldImmutable.parts, part) then
			ZoneListener_setupPartTracking(self, part, nil)
		end
	end
	for _, part in oldImmutable.parts do
		if not table.find(newImmutable.parts, part) then
			ZoneListener_cleanupPartTracking(self, part)
		end
	end

	-- Attachments
	for _, attachment in newImmutable.attachments do
		if not table.find(oldImmutable.attachments, attachment) then
			ZoneListener_setupAttachmentTracking(self, attachment)
		end
	end
	for _, attachment in oldImmutable.attachments do
		if not table.find(newImmutable.attachments, attachment) then
			ZoneListener_cleanupAttachmentTracking(self, attachment)
		end
	end

	-- PVInstances
	for _, pvi in newImmutable.pvinstances do
		if not table.find(oldImmutable.pvinstances, pvi) then
			ZoneListener_setupPVInstanceTracking(self, pvi)
		end
	end
	for _, pvi in oldImmutable.pvinstances do
		if not table.find(newImmutable.pvinstances, pvi) then
			ZoneListener_cleanupPVInstanceTracking(self, pvi)
		end
	end

	-- Models
	for _, model in newImmutable.models do
		if not table.find(oldImmutable.models, model) then
			ZoneListener_setupModelTracking(self, model)
		end
	end
	for _, model in oldImmutable.models do
		if not table.find(newImmutable.models, model) then
			ZoneListener_cleanupModelTracking(self, model)
		end
	end

	-- Players
	for _, player in newImmutable.players do
		if not table.find(oldImmutable.players, player) then
			ZoneListener_setupPlayerTracking(self, player)
		end
	end
	for _, player in oldImmutable.players do
		if not table.find(newImmutable.players, player) then
			ZoneListener_cleanupPlayerTracking(self, player)
		end
	end
end

function ZoneListener:onEnter(fn)
	local data = self.data
	table.insert(data.enterObservers, fn)

	return function()
		local index = table.find(data.enterObservers, fn)
		if index then table.remove(data.enterObservers, index) end
	end
end

function ZoneListener:onExit(fn)
	local data = self.data
	table.insert(data.exitObservers, fn)

	return function()
		local index = table.find(data.exitObservers, fn)
		if index then table.remove(data.exitObservers, index) end
	end
end

function ZoneListener:observe(fn)
	for _, part in self.itemsInside.parts do
		noyieldcall(fn, {part = part})
	end
	for _, attachment in self.itemsInside.attachments do
		noyieldcall(fn, {attachment = attachment})
	end
	for _, pvi in self.itemsInside.pvinstances do
		noyieldcall(fn, {pvinstance = pvi})
	end
	for _, model in self.itemsInside.models do
		local modelPlayer = Players:GetPlayerFromCharacter(model)
		noyieldcall(fn, {model = model, player = modelPlayer})
	end
	for _, player in self.itemsInside.players do
		noyieldcall(fn, {player = player, model = player.Character})
	end
	
	return self:onEnter(function(item)
		local cleanup = fn(item)
		if cleanup then
			local disconnect; disconnect = self:onExit(function(newItem)
				if newItem.player ~= item.player then return end
				if newItem.part ~= item.part then return end
				if newItem.model ~= item.model then return end
				if newItem.attachment ~= item.attachment then return end
				if newItem.pvinstance ~= item.pvinstance then return end

				cleanup()
				disconnect()
			end)
		end
	end)
end

local function ZoneListener_checkAndUpdatePart(self: ZoneListener, zone: Zone, part: BasePart, owner: Model | Player | nil)
	local data = self.data
	local precision = self.precision
	local queryShape = self.queryShape
	
	if data.stopped then return end
	--if not part:IsDescendantOf(game) then return end

	local isInsideAny = false
	local shape
	for _, z in self.zones do
		z:rebuildIfDirty()

		local isInside
		if queryShape == "Point" then
			isInside = checkPointInGroup(part.Position :: any, z.bvh)
		else
			isInside = checkPartInGroup(part, z.bvh)
		end

		if isInside then
			shape = isInside
			isInsideAny = true
			break
		end
	end

	local wasInside = data.partsSet[part]

	if isInsideAny and not wasInside then
		table.insert(self.itemsInside.parts, part)
		data.partsSet[part] = true

		if owner then
			if typeof(owner) == "Instance" and owner:IsA("Model") then
				local model = owner :: Model
				if not data.modelPartsInside[model] then
					data.modelPartsInside[model] = {}
				end
				table.insert(data.modelPartsInside[model], part)

				if #data.modelPartsInside[model] == 1 then
					table.insert(self.itemsInside.models, model)
					
					data.itemToZoneAndShape[model] = {shape = shape, zone = zone}
					local modelPlayer = Players:GetPlayerFromCharacter(model)
					local item = {model = model, player = modelPlayer, shape = shape, zone = zone}
					for _, observer in data.enterObservers do
						noyieldcall(observer, item)
					end
				end
			elseif typeof(owner) == "Instance" and owner:IsA("Player") then
				local player = owner :: Player
				if not data.playerPartsInside[player] then
					data.playerPartsInside[player] = {}
				end
				table.insert(data.playerPartsInside[player], part)

				if #data.playerPartsInside[player] == 1 then
					table.insert(self.itemsInside.players, player)
					
					data.itemToZoneAndShape[player] = {shape = shape, zone = zone}
					local item = {player = player, model = player.Character, shape = shape, zone = zone}
					for _, observer in data.enterObservers do
						noyieldcall(observer, item)
					end
				end
			end
		else
			data.itemToZoneAndShape[part] = {shape = shape, zone = zone}
			local item = {part = part, shape = shape, zone = zone}
			for _, observer in data.enterObservers do
				noyieldcall(observer, item)
			end
		end
	elseif not isInsideAny and wasInside then
		local index = table.find(self.itemsInside.parts, part)
		if index then table.remove(self.itemsInside.parts, index) end
		data.partsSet[part] = nil

		if owner then
			if typeof(owner) == "Instance" and owner:IsA("Model") then
				local model = owner :: Model
				if data.modelPartsInside[model] then
					local partIndex = table.find(data.modelPartsInside[model], part)
					if partIndex then table.remove(data.modelPartsInside[model], partIndex) end

					if #data.modelPartsInside[model] == 0 then
						data.modelPartsInside[model] = nil
						local modelIndex = table.find(self.itemsInside.models, model)
						if modelIndex then table.remove(self.itemsInside.models, modelIndex) end
						local modelPlayer = Players:GetPlayerFromCharacter(model)
						
						data.itemToZoneAndShape[model] = nil
						local item = {model = model, player = modelPlayer, shape = shape, zone = zone}
						for _, observer in data.exitObservers do
							noyieldcall(observer, item)
						end
					end
				end
			elseif typeof(owner) == "Instance" and owner:IsA("Player") then
				local player = owner :: Player
				if data.playerPartsInside[player] then
					local partIndex = table.find(data.playerPartsInside[player], part)
					if partIndex then table.remove(data.playerPartsInside[player], partIndex) end

					if #data.playerPartsInside[player] == 0 then
						data.playerPartsInside[player] = nil
						local playerIndex = table.find(self.itemsInside.players, player)
						if playerIndex then table.remove(self.itemsInside.players, playerIndex) end
						
						data.itemToZoneAndShape[player] = nil
						local item = {player = player, model = player.Character, shape = shape, zone = zone}
						for _, observer in data.exitObservers do
							noyieldcall(observer, item)
						end
					end
				end
			end
		else
			data.itemToZoneAndShape[part] = nil
			local item = {part = part, shape = shape, zone = zone}
			for _, observer in data.exitObservers do
				noyieldcall(observer, item)
			end
		end
	end
end

local function ZoneListener_checkAndUpdateAttachment(self: ZoneListener, zone: Zone, attachment: Attachment)
	local data = self.data
	local precision = self.precision
	local queryShape = self.queryShape
	
	if data.stopped then return end
	--if not attachment:IsDescendantOf(game) then return end

	local pos = getAttachmentWorldPosition(attachment)

	local isInsideAny = false
	local shape
	for _, z in self.zones do
		z:rebuildIfDirty()
		local result = checkPointInGroup(pos, z.bvh)
		if result then
			shape = result
			isInsideAny = true
			break
		end
	end

	local wasInside = data.attachmentsSet[attachment]

	if isInsideAny and not wasInside then
		table.insert(self.itemsInside.attachments, attachment)
		data.attachmentsSet[attachment] = true
		
		data.itemToZoneAndShape[attachment] = {shape = shape, zone = zone}
		local item = {attachment = attachment, shape = shape, zone = zone}
		for _, observer in data.enterObservers do
			noyieldcall(observer, item)
		end
	elseif not isInsideAny and wasInside then
		local index = table.find(self.itemsInside.attachments, attachment)
		if index then table.remove(self.itemsInside.attachments, index) end
		data.attachmentsSet[attachment] = nil
		
		data.itemToZoneAndShape[attachment] = nil
		local item = {attachment = attachment, shape = shape, zone = zone}
		for _, observer in data.exitObservers do
			noyieldcall(observer, item)
		end
	end
end

local function ZoneListener_checkAndUpdatePVInstance(self: ZoneListener, zone: Zone, pvi: PVInstance)
	local data = self.data
	local precision = self.precision
	local queryShape = self.queryShape
	
	if data.stopped then return end
	--if not pvi:IsDescendantOf(game) then return end

	local isInsideAny = false
	local shape
	for _, z in self.zones do
		z:rebuildIfDirty()

		local inside
		if queryShape == "Point" then
			local pivot = pvi:GetPivot()
			inside = z:getShapeWithPoint(pivot.Position :: any)
		else
			local cf, size = getPVInstanceBounds(pvi)
			inside = z:getShapeWithBox(cf, size)
		end

		if inside then
			shape = inside
			isInsideAny = true
			break
		end
	end

	local wasInside = data.pvinstancesSet[pvi]

	if isInsideAny and not wasInside then
		table.insert(self.itemsInside.pvinstances, pvi)
		data.pvinstancesSet[pvi] = true
		
		data.itemToZoneAndShape[pvi] = {shape = shape, zone = zone}
		
		local item = {pvinstance = pvi, shape = shape, zone = zone}
		for _, observer in data.enterObservers do
			noyieldcall(observer, item)
		end
	elseif not isInsideAny and wasInside then
		local index = table.find(self.itemsInside.pvinstances, pvi)
		if index then table.remove(self.itemsInside.pvinstances, index) end
		data.pvinstancesSet[pvi] = nil
		
		data.itemToZoneAndShape[pvi] = nil
		
		local item = {pvinstance = pvi, shape = shape, zone = zone}
		for _, observer in data.exitObservers do
			noyieldcall(observer, item)
		end
	end
end

local function ZoneListener_checkAndUpdateModel(self: ZoneListener, zone: Zone, model: Model)
	local data = self.data
	local precision = self.precision
	local queryShape = self.queryShape
	
	if data.stopped then return end
	--if not model:IsDescendantOf(game) then return end

	local isBoxInZoneAny = false
	local shape
	for _, z in self.zones do
		z:rebuildIfDirty()

		local isBoxInZone
		if queryShape == "Point" then
			local pivot = model:GetPivot().Position
			isBoxInZone = z:getShapeWithPoint(pivot :: any)
		else
			local cf, size = model:GetBoundingBox()
			isBoxInZone = z:getShapeWithBox(cf, size :: any)
		end

		if isBoxInZone then
			shape = isBoxInZone
			isBoxInZoneAny = true
			break
		end
	end

	local wasInside = data.modelPartsInside[model] ~= nil

	if precision == "BoundingBox" then
		if isBoxInZoneAny and not wasInside then
			data.modelPartsInside[model] = {}
			table.insert(self.itemsInside.models, model)
			local modelPlayer = Players:GetPlayerFromCharacter(model)
			
			data.itemToZoneAndShape[model] = {shape = shape, zone = zone}
			
			local item = {model = model, player = modelPlayer, shape = shape, zone = zone}
			for _, observer in data.enterObservers do
				noyieldcall(observer, item)
			end
		elseif not isBoxInZoneAny and wasInside then
			data.modelPartsInside[model] = nil
			local modelIndex = table.find(self.itemsInside.models, model)
			if modelIndex then table.remove(self.itemsInside.models, modelIndex) end
			local modelPlayer = Players:GetPlayerFromCharacter(model)
			
			data.itemToZoneAndShape[model] = nil
			
			local item = {model = model, player = modelPlayer, shape = shape, zone = zone}
			for _, observer in data.exitObservers do
				noyieldcall(observer, item)
			end
		end
		return
	end

	-- Part mode: early-out if bounding box is already outside all zones
	if not isBoxInZoneAny then
		if data.modelPartsInside[model] then
			for _, part in data.modelPartsInside[model] do
				local index = table.find(self.itemsInside.parts, part)
				if index then table.remove(self.itemsInside.parts, index) end
				data.partsSet[part] = nil
			end

			data.modelPartsInside[model] = nil
			local modelIndex = table.find(self.itemsInside.models, model)
			if modelIndex then table.remove(self.itemsInside.models, modelIndex) end
			
			data.itemToZoneAndShape[model] = nil
			
			local modelPlayer = Players:GetPlayerFromCharacter(model)
			local item = {model = model, player = modelPlayer, shape = shape, zone = zone}
			for _, observer in data.exitObservers do
				noyieldcall(observer, item)
			end
		end
		return
	end
	
	local parts = getPartsFromModel(model)
	for _, part in parts do
		ZoneListener_checkAndUpdatePart(self, zone, part, model)
	end
end

local function ZoneListener_checkAndUpdatePlayer(self: ZoneListener, zone: Zone, player: Player)
	local data = self.data
	local precision = self.precision
	local queryShape = self.queryShape
	
	if data.stopped then return end
	local character = player.Character
	if not character then return end
	--if not character or not character:IsDescendantOf(game) then return end

	local isBoxInZoneAny = false
	local shape
	for _, z in self.zones do
		z:rebuildIfDirty()

		local isBoxInZone
		if queryShape == "Point" then
			local pivot = character:GetPivot().Position
			isBoxInZone = z:getShapeWithPoint(pivot :: any)
		else
			local cf, size = character:GetBoundingBox()
			isBoxInZone = z:getShapeWithBox(cf, size :: any)
		end

		if isBoxInZone then
			shape = isBoxInZone
			isBoxInZoneAny = true
			break
		end
	end

	local wasInside = data.playerPartsInside[player] ~= nil

	if precision == "BoundingBox" then
		if isBoxInZoneAny and not wasInside then
			data.playerPartsInside[player] = {}
			table.insert(self.itemsInside.players, player)
			
			data.itemToZoneAndShape[player] = {shape = shape, zone = zone}
			
			local item = {player = player, model = player.Character, shape = shape, zone = zone}
			for _, observer in data.enterObservers do
				noyieldcall(observer, item)
			end
		elseif not isBoxInZoneAny and wasInside then
			data.playerPartsInside[player] = nil
			local playerIndex = table.find(self.itemsInside.players, player)
			if playerIndex then table.remove(self.itemsInside.players, playerIndex) end
			
			data.itemToZoneAndShape[player] = nil
			
			local item = {player = player, model = player.Character, shape = shape, zone = zone}
			for _, observer in data.exitObservers do
				noyieldcall(observer, item)
			end
		end
		return
	end
	
	if not isBoxInZoneAny then
		if data.playerPartsInside[player] then
			for _, part in data.playerPartsInside[player] do
				local index = table.find(self.itemsInside.parts, part)
				if index then table.remove(self.itemsInside.parts, index) end
				data.partsSet[part] = nil
			end

			data.playerPartsInside[player] = nil
			local playerIndex = table.find(self.itemsInside.players, player)
			if playerIndex then table.remove(self.itemsInside.players, playerIndex) end
			
			data.itemToZoneAndShape[player] = nil
			
			local item = {player = player, model = player.Character, shape = shape, zone = zone}
			for _, observer in data.exitObservers do
				noyieldcall(observer, item)
			end
		end
		return
	end

	local parts = getPartsFromModel(character)
	for _, part in parts do
		ZoneListener_checkAndUpdatePart(self, zone, part, player)
	end
end

function ZoneListener:subscribe(zone: Zone)
	if table.find(self.zones, zone) then return end

	table.insert(self.zones, zone)

	local scheduler = ZoneScheduler.getGlobal()
	if not table.find(scheduler.listeners, self) then
		ZoneScheduler.registerListener(self)
	end

	zone:rebuildIfDirty()

	for _, group in self.groups do
		checkTrackGroupImmutable(group.immutable)
		for _, part in group.immutable.parts do
			ZoneListener_setupPartTracking(self, part, nil)
		end
		for _, attachment in group.immutable.attachments do
			ZoneListener_setupAttachmentTracking(self, attachment)
		end
		for _, pvi in group.immutable.pvinstances do
			ZoneListener_setupPVInstanceTracking(self, pvi)
		end
		for _, model in group.immutable.models do
			ZoneListener_setupModelTracking(self, model)
		end
		for _, player in group.immutable.players do
			ZoneListener_setupPlayerTracking(self, player)
		end
	end
end

function ZoneListener:unsubscribe(zone)
	local index = table.find(self.zones, zone)
	if not index then return end

	table.remove(self.zones, index)
	
	if #self.zones == 0 then
		ZoneListener_cleanupAllTracking(self)
	end
end

function ZoneListener:unsubscribeAll()
	table.clear(self.zones)
	ZoneListener_cleanupAllTracking(self)
end

function ZoneListener:setGroups(groups)
	for _, group in groups do
		if not table.find(group.listeners, self) then
			table.insert(group.listeners, self)
		end
	end

	for _, group in self.groups do
		if not table.find(groups, group) then
			local idx = table.find(group.listeners, self)
			if idx then table.remove(group.listeners, idx) end
		end
	end

	self.groups = groups

	if #self.zones > 0 then
		ZoneListener_cleanupAllTracking(self)

		local zones = table.clone(self.zones)
		table.clear(self.zones)

		for _, zone in zones do
			self:subscribe(zone)
		end
	end
end

function ZoneListener__iter(self: ZoneListener)
	local t1 = self.itemsInside.parts
	local t2 = self.itemsInside.attachments
	local t3 = self.itemsInside.pvinstances
	local t4 = self.itemsInside.players
	local t5 = self.itemsInside.models
	local itemToShapeAndZone = self.data.itemToZoneAndShape
	local current: any = t1
	local currentLen = #t1
	local idx = 0

	return function()
		idx += 1

		-- Advance to the next non-empty table when the current one is exhausted
		while idx > currentLen do
			if current == t1 then current = t2
			elseif current == t2 then current = t3
			elseif current == t3 then current = t4
			elseif current == t4 then current = t5
			else return nil :: any
			end
			currentLen = #current
			idx = 1
		end

		if current == t1 then
			local item = current[idx]
			local info = itemToShapeAndZone[item]
			if info then
				return {part = item, shape = info.shape, zone = info.zone}
			else
				return {part = item}
			end
		elseif current == t2 then
			local item = current[idx]
			local info = itemToShapeAndZone[item]
			if info then
				return {attachment = item, shape = info.shape, zone = info.zone}
			else
				return {attachment = item}
			end
		elseif current == t3 then
			local item = current[idx]
			local info = itemToShapeAndZone[item]
			if info then
				return {pvinstance = item, shape = info.shape, zone = info.zone}
			else
				return {pvinstance = item}
			end
		elseif current == t4 then
			local item = current[idx]
			local info = itemToShapeAndZone[item]
			if info then
				return {player = item, model = item.Character, shape = info.shape, zone = info.zone}
			else
				return {player = item, model = item.Character}
			end
		elseif current == t5 then
			local model = current[idx]
			local modelPlayer = Players:GetPlayerFromCharacter(model)
			local info = itemToShapeAndZone[model]
			if info then
				return {model = model, player = modelPlayer, shape = info.shape, zone = info.zone}
			else
				return {model = model, player = modelPlayer}
			end
		end

		return nil :: any
	end
end
local ZoneListenerMt = {__iter = ZoneListener__iter}

local function createListener(configs: {precision: ("BoundingBox" | "Part")?, queryShape: ("Point" | "Box")?, groups: {TrackGroup}?, zones: {Zone}?}): ZoneListener
	local listener: ZoneListener = setmetatable({
		onEnter = ZoneListener.onEnter,
		onExit = ZoneListener.onExit,
		observe = ZoneListener.observe,
		subscribe = ZoneListener.subscribe,
		unsubscribe = ZoneListener.unsubscribe,
		unsubscribeAll = ZoneListener.unsubscribeAll,
		setGroups = ZoneListener.setGroups,
		iter = ZoneListener__iter,

		groups = {},
		zones = {},
		itemsInside = {
			parts = {},
			attachments = {},
			pvinstances = {},
			models = {},
			players = {}
		},
		precision = (configs.precision or "Part") :: any,
		queryShape = (configs.queryShape or "Box") :: any,
		data = {
			partsSet = {},
			attachmentsSet = {},
			pvinstancesSet = {},
			partToModel = {},
			partToPlayer = {},
			modelPartsInside = {},
			playerPartsInside = {},
			enterObservers = {},
			exitObservers = {},
			stopped = false,
			partConnections = {},
			attachmentConnections = {},
			pvinstanceConnections = {},
			modelConnections = {},
			playerConnections = {},
			itemToZoneAndShape = {}
		}
	}, ZoneListenerMt)
	if configs.groups then
		listener:setGroups(configs.groups)
	end
	if configs.zones then
		for _, zone in configs.zones do
			listener:subscribe(zone)
		end
	end

	return listener :: any
end

local function createZone(shapeInstances: {ShapeInstance}?, metadata: {[string]: any}?): Zone
	local zone = {
		getRandomPoint = Zone.getRandomPoint,
		isPointInZone = Zone.isPointInZone,
		isBoxInZone = Zone.isBoxInZone,
		getShapeWithPoint = Zone.getShapeWithPoint,
		getShapeWithBox = Zone.getShapeWithBox,
		rebuild = Zone.rebuild,
		rebuildIfDirty = Zone.rebuildIfDirty,
		
		bvhRestructureWeight = 1,
		shapes = {},
		bvh = Geometry.Bvh.createBVH({}),
		bvhDirty = true,
		boxes = {},
		metadata = metadata or {}
	}
	
	if shapeInstances then
		for _, shapeInstance in shapeInstances do
			shapeInstance:attach(zone)
		end
	end
	zone:rebuild()
	
	return zone
end

local function createMeshShape(mesh: MeshPart, cframe: CFrame?): MeshShape
	local clonedMesh = Instance.fromExisting(mesh)
	clonedMesh.Anchored = true
	clonedMesh.CFrame = CFrame.identity
	clonedMesh.CanCollide = false
	clonedMesh.CanQuery = true
	clonedMesh.CanTouch = false
	clonedMesh.Parent = worldModel

	return {
		ty = "Mesh",
		transform = cframe or CFrame.identity,
		size = mesh.ExtentsSize :: any,
		mesh = clonedMesh,
	}
end

local function createShapeInstance(shape: Shape, metadata: {[string]: any}?): ShapeInstance
	local shapeinst = {
		shape = shape,
		zones = {},
		
		toParts = ShapeInstance.toParts,
		syncWithPart = ShapeInstance.syncWithPart,
		syncWithAttachment = ShapeInstance.syncWithAttachment,
		attach = ShapeInstance.attach,
		detach = ShapeInstance.detach,
		detachAll = ShapeInstance.detachAll,

		cframe = CFrame.identity,
		scale = vector.one,
		metadata = metadata or {}
	}
	
	return shapeinst
end

local function createShape(part: BasePart | Model): Shape
	if part:IsA("Part") then
		local shape = part.Shape

		if shape == Enum.PartType.Block then
			return {
				ty = "Box",
				transform = CFrame.identity,
				size = part.ExtentsSize :: any
			}
		elseif shape == Enum.PartType.Ball then
			local radius = part.ExtentsSize.X / 2
			return {
				ty = "Sphere",
				center = Vector3.zero :: any,
				radius = radius,
			}
		elseif shape == Enum.PartType.Cylinder then
			local height = part.ExtentsSize.X
			local radius = part.ExtentsSize.Y / 2
			local axis = Vector3.xAxis * height

			return {
				ty = "Cylinder",
				center = Vector3.zero :: any,
				axis = axis :: any,
				radius = radius,
				transform = CFrame.identity,
				size = part.ExtentsSize :: any,
			}
		elseif shape == Enum.PartType.Wedge then
			return {
				ty = "Wedge",
				transform = CFrame.identity,
				size = part.ExtentsSize :: any,
			}
		end
	elseif part:IsA("MeshPart") then
		return createMeshShape(part, CFrame.identity)
	elseif part:IsA("WedgePart") then
		return {
			ty = "Wedge",
			transform = CFrame.identity,
			size = part.ExtentsSize :: any,
		}
	elseif part:IsA("CornerWedgePart") then
		return {
			ty = "Wedge",
			transform = CFrame.identity,
			size = part.ExtentsSize :: any,
		}
	elseif part:IsA("Model") then
		local cframe, size = part:GetBoundingBox()
		return {
			ty = "Box",
			transform = CFrame.identity,
			size = size :: any
		}
	end

	return {
		ty = "Box",
		transform = CFrame.identity,
		size = vector.one :: any
	}
end

local function shapeInstanceFromPart(part: BasePart | Model): ShapeInstance
	local shapeInstance = createShapeInstance(createShape(part))
	if part:IsA("BasePart") then
		shapeInstance.cframe = part.CFrame
	elseif part:IsA("Model") then
		shapeInstance.cframe = part:GetBoundingBox()
	end
	return shapeInstance
end

local TrackGroup = {} :: TrackGroup

function TrackGroup:update()
	local oldImmutable = self.immutable

	self.immutable = {
		parts = table.freeze(table.clone(self.mutable.parts)),
		attachments = table.freeze(table.clone(self.mutable.attachments)),
		pvinstances = table.freeze(table.clone(self.mutable.pvinstances)),
		models = table.freeze(table.clone(self.mutable.models)),
		players = table.freeze(table.clone(self.mutable.players))
	}

	for _, listener in self.listeners do
		ZoneListener_incrementalUpdate(listener, oldImmutable, self.immutable)
	end
end

function TrackGroup:removeFrom(listener)
	local idx = table.find(self.listeners, listener)
	if idx then
		table.remove(self.listeners, idx)
		local listenerIdx = table.find(listener.groups, self)
		if listenerIdx then
			table.remove(listener.groups, listenerIdx)

			if #listener.zones > 0 then
				ZoneListener_cleanupAllTracking(listener)

				local zones = table.clone(listener.zones)
				table.clear(listener.zones)

				for _, zone in zones do
					listener:subscribe(zone)
				end
			end
		end
	end
end

local function TrackGroup_checkIsInGroup(self: TrackGroup, name: string, item: any)
	if not item then return false end
	local tbl = self.mutable[name]
	local immut = self.immutable[name]
	return table.find(tbl, item) ~= nil or table.find(immut, item) ~= nil
end

local function findAndRemove(tbl, item)
	local idx = table.find(tbl, item)
	if idx then
		table.remove(tbl, idx)
	end
end

function TrackGroup:addItem(item)
	if TrackGroup_checkIsInGroup(self, "parts", item.part)
		or TrackGroup_checkIsInGroup(self, "attachments", item.attachment)
		or TrackGroup_checkIsInGroup(self, "pvinstances", item.pvinstance)
		or TrackGroup_checkIsInGroup(self, "models", item.model)
		or TrackGroup_checkIsInGroup(self, "players", item.player) then
		return
	end
	if item.part then
		table.insert(self.mutable.parts, item.part)
		self:update()
	elseif item.attachment then
		table.insert(self.mutable.attachments, item.attachment)
		self:update()
	elseif item.pvinstance then
		table.insert(self.mutable.pvinstances, item.pvinstance)
		self:update()
	elseif item.model then
		table.insert(self.mutable.models, item.model)
		self:update()
	elseif item.player then
		table.insert(self.mutable.players, item.player)
		self:update()
	end
end

function TrackGroup:removeItem(item)
	if not TrackGroup_checkIsInGroup(self, "parts", item.part)
		and not TrackGroup_checkIsInGroup(self, "attachments", item.attachment)
		and not TrackGroup_checkIsInGroup(self, "pvinstances", item.pvinstance)
		and not TrackGroup_checkIsInGroup(self, "models", item.model)
		and not TrackGroup_checkIsInGroup(self, "players", item.player) then
		return
	end
	if item.part then
		findAndRemove(self.mutable.parts, item.part)
		self:update()
	elseif item.attachment then
		findAndRemove(self.mutable.attachments, item.attachment)
		self:update()
	elseif item.pvinstance then
		findAndRemove(self.mutable.pvinstances, item.pvinstance)
		self:update()
	elseif item.model then
		findAndRemove(self.mutable.models, item.model)
		self:update()
	elseif item.player then
		findAndRemove(self.mutable.players, item.player)
		self:update()
	end
end

function TrackGroup:addItems(items)
	local updated = false
	if items.parts then
		for _, v in items.parts do
			if not TrackGroup_checkIsInGroup(self, "parts", v) then
				updated = true
				table.insert(self.mutable.parts, v)
			end
		end
	end
	if items.attachments then
		for _, v in items.attachments do
			if not TrackGroup_checkIsInGroup(self, "attachments", v) then
				updated = true
				table.insert(self.mutable.attachments, v)
			end
		end
	end
	if items.pvinstances then
		for _, v in items.pvinstances do
			if not TrackGroup_checkIsInGroup(self, "pvinstances", v) then
				updated = true
				table.insert(self.mutable.pvinstances, v)
			end
		end
	end
	if items.models then
		for _, v in items.models do
			if not TrackGroup_checkIsInGroup(self, "models", v) then
				updated = true
				table.insert(self.mutable.models, v)
			end
		end
	end
	if items.players then
		for _, v in items.players do
			if not TrackGroup_checkIsInGroup(self, "players", v) then
				updated = true
				table.insert(self.mutable.players, v)
			end
		end
	end
	if updated then
		self:update()
	end
end

function TrackGroup:removeItems(items)
	local updated = false
	if items.parts then
		for _, v in items.parts do
			if TrackGroup_checkIsInGroup(self, "parts", v) then
				updated = true
				findAndRemove(self.mutable.parts, v)
			end
		end
	end
	if items.attachments then
		for _, v in items.attachments do
			if TrackGroup_checkIsInGroup(self, "attachments", v) then
				updated = true
				findAndRemove(self.mutable.attachments, v)
			end
		end
	end
	if items.pvinstances then
		for _, v in items.pvinstances do
			if TrackGroup_checkIsInGroup(self, "pvinstances", v) then
				updated = true
				findAndRemove(self.mutable.pvinstances, v)
			end
		end
	end
	if items.models then
		for _, v in items.models do
			if TrackGroup_checkIsInGroup(self, "models", v) then
				updated = true
				findAndRemove(self.mutable.models, v)
			end
		end
	end
	if items.players then
		for _, v in items.players do
			if TrackGroup_checkIsInGroup(self, "players", v) then
				updated = true
				findAndRemove(self.mutable.players, v)
			end
		end
	end
	if updated then
		self:update()
	end
end

function TrackGroup:clear()
	self.mutable = {
		parts = {},
		models = {},
		players = {},
		attachments = {},
		pvinstances = {}
	}
	self.immutable = {
		parts = {},
		models = {},
		players = {},
		attachments = {},
		pvinstances = {}
	}
	self:update()
end

type optionalitems = {parts: {BasePart}?, attachments: {Attachment}?, pvinstances: {PVInstance}?, models: {Model}?, players: {Player}?}
local function TrackGroup_new(items: optionalitems?): TrackGroup
	local items: optionalitems = items or {}
	
	local group = {
		update = TrackGroup.update,
		removeFrom = TrackGroup.removeFrom,
		addItem = TrackGroup.addItem,
		addItems = TrackGroup.addItems,
		removeItem = TrackGroup.removeItem,
		removeItems = TrackGroup.removeItems,
		clear = TrackGroup.clear,

		mutable = {
			parts = items.parts or {},
			attachments = items.attachments or {},
			pvinstances = items.pvinstances or {},
			models = items.models or {},
			players = items.players or {}
		},
		immutable = {
			parts = {},
			attachments = {},
			pvinstances = {},
			models = {},
			players = {}
		},
		listeners = {}
	}
	
	group:update()

	return group
end

local function TrackGroup_forTag(tag: string): (TrackGroup, Types.Disconnector)
	local items = {
		parts = {},
		attachments = {},
		pvinstances = {},
		models = {},
		players = {}
	}
	for _, item in CollectionService:GetTagged(tag) do
		if item:IsA("BasePart") then
			table.insert(items.parts, item)
		elseif item:IsA("Attachment") then
			table.insert(items.attachments, item)
		elseif item:IsA("Model") then
			table.insert(items.models, item)
		elseif item:IsA("Player") then
			table.insert(items.players, item)
		elseif item:IsA("PVInstance") then
			table.insert(items.pvinstances, item)
		end
	end
	local group = TrackGroup_new(items)
	
	local onAdded = CollectionService:GetInstanceAddedSignal(tag):Connect(function(item: Instance)
		if item:IsA("BasePart") then
			group:addItem({part = item})
		elseif item:IsA("Attachment") then
			group:addItem({attachment = item})
		elseif item:IsA("Model") then
			group:addItem({model = item})
		elseif item:IsA("Player") then
			group:addItem({player = item})
		elseif item:IsA("PVInstance") then
			group:addItem({pvinstance = item})
		end
	end)
	local onRemoved = CollectionService:GetInstanceRemovedSignal(tag):Connect(function(item: Instance)
		if item:IsA("BasePart") then
			group:removeItem({part = item})
		elseif item:IsA("Attachment") then
			group:removeItem({attachment = item})
		elseif item:IsA("Model") then
			group:removeItem({model = item})
		elseif item:IsA("Player") then
			group:removeItem({player = item})
		elseif item:IsA("PVInstance") then
			group:removeItem({pvinstance = item})
		end
	end)
	return group, function()
		onAdded:Disconnect()
		onRemoved:Disconnect()
	end
end

local function getZonesAtPoint(zones: {Zone}, point: vector): {Zone}
	local zonesAtPoint = {}

	for _, zone in zones do
		if zone:isPointInZone(point) then
			table.insert(zonesAtPoint, zone)
		end
	end

	return zonesAtPoint
end

ZoneScheduler.registerCallbacks({
	checkPart = ZoneListener_checkAndUpdatePart,
	checkModel = ZoneListener_checkAndUpdateModel,
	checkPlayer = ZoneListener_checkAndUpdatePlayer,
	checkAttachment = ZoneListener_checkAndUpdateAttachment,
	checkPVInstance = ZoneListener_checkAndUpdatePVInstance
})

local defaultGroups = {} do
	defaultGroups.players = TrackGroup_new({players = Players:GetPlayers()}); do
		Players.PlayerAdded:Connect(function(player)
			defaultGroups.players:addItem({player = player})
		end)
		Players.PlayerRemoving:Connect(function(player)
			defaultGroups.players:removeItem({player = player})
		end)
	end
	defaultGroups.localPlayer = TrackGroup_new(); do
		if RunService:IsClient() then
			local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()
			defaultGroups.localPlayer:addItem({player = LocalPlayer})
		end
	end
end

return table.freeze({
	zshape = require("@self/ZShape"),
	new = createZone,
	forParts = function(parts: {Instance}, metadata: {[string]: any}?)
		local shapes = {}
		for _, v in parts do
			if not v:IsA("BasePart") then continue end
			local shape = shapeInstanceFromPart(v)
			shape:syncWithPart(v)
			table.insert(shapes, shape)
		end
		return createZone(shapes, metadata)
	end,
	forTag = function(tag: string, metadata: {[string]: any}?)
		local shapes = {}
		for _, v in CollectionService:GetTagged(tag) do
			if not v:IsA("BasePart") then continue end
			table.insert(shapes, shapeInstanceFromPart(v))
		end
		
		local zone = createZone(shapes, metadata)
		local instToShape: {[Instance]: ShapeInstance} = {}
		
		local function added(inst: Instance)
			if not inst:IsA("BasePart") then return end
			
			local shape = shapeInstanceFromPart(inst)
			instToShape[inst] = shape
			
			shape:attach(zone)
			shape:syncWithPart(inst)
		end
		
		local function removed(inst: Instance)
			if not inst:IsA("BasePart") then return end
			
			local shape = instToShape[inst]
			if not shape then return end
			
			shape:detach(zone)
		end
		
		local onAdded = CollectionService:GetInstanceAddedSignal(tag):Connect(added)
		local onRemoved = CollectionService:GetInstanceRemovedSignal(tag):Connect(removed)
		
		return zone, function()
			onAdded:Disconnect()
			onRemoved:Disconnect()
		end
	end,
	shape = {
		new = (function(ty: "Box" | "Cylinder" | "Wedge" | "Sphere" | "Group" | "Mesh", a: any, b: any, c: any): Shape
			if ty == "Box" then
				return {
					ty = "Box",
					transform = a or CFrame.identity,
					size = b or vector.zero
				}
			elseif ty == "Sphere" then
				return {
					ty = "Sphere",
					center = a or vector.zero,
					radius = b or 0,
				}
			elseif ty == "Cylinder" then
				return {
					ty = "Cylinder",
					center = if a then a.Position else vector.zero,
					axis = if a then a.XVector.Unit * b else vector.create(b, 0, 0),
					radius = c or 0,
					transform = a or CFrame.identity,
					size = if b then vector.create(b, c + c, c + c) else vector.zero,
				}
			elseif ty == "Wedge" then
				return {
					ty = "Wedge",
					transform = a or CFrame.identity,
					size = b or vector.zero,
				}
			elseif ty == "Group" then
				return {
					ty = "Group",
					transform = a or CFrame.identity,
					shapes = b or {}
				}
			elseif ty == "Mesh" then
				local shape = createMeshShape(a, b or CFrame.identity)
				shape.size = c or vector.zero
				return shape
			end
			error("exhaustive")
		end :: any) ::
		& ((shape: "Box", transform: CFrame?, size: vector?) -> BoxShape)
		& ((shape: "Sphere", center: vector?, radius: number?) -> SphereShape)
		& ((shape: "Wedge", transform: CFrame?, size: vector?) -> WedgeShape)
		& ((shape: "Cylinder", transform: CFrame?, height: number?, radius: number?) -> CylinderShape)
		& ((shape: "Group", transform: CFrame?, shapes: {Shape}?) -> GroupShape)
		& ((shape: "Mesh", meshPart: MeshPart, transform: CFrame?, size: vector?) -> MeshShape),
		fromPart = createShape,
	},
	shapeInstance = {
		new = createShapeInstance,
		fromPart = shapeInstanceFromPart,
	},
	listener = {
		new = createListener,
	},
	trackGroup = {
		new = TrackGroup_new,
		forTag = TrackGroup_forTag,
		
		players = defaultGroups.players,
		localPlayer = defaultGroups.localPlayer
	},
	getZonesAtPoint = getZonesAtPoint,
	
	getZoneVisualizer = function(zone: Zone)
		local visualizer = {
			update = function(self: ZoneVisualizer, parent: Instance?)
				self:destroy()
				local parts = Geometry.Bvh.visualize(zone.bvh)
				for _, v in parts do
					v.Parent = parent
				end
				self.currentParts = (parts :: {Part}?)
			end,
			destroy = function(self: ZoneVisualizer)
				if self.currentParts then
					for _, v in self.currentParts do
						v:Destroy()
					end
					self.currentParts = nil
				end
			end,
			currentParts = (nil :: any)::{Part}?
		}
		type ZoneVisualizer = typeof(visualizer)
		return visualizer :: ZoneVisualizer
	end,
	geometry = Geometry
})
