--!optimize 2
--!strict
--!native

--[[
	Utility module to create a Bounding Volume Hierarchy
	from an array of boxes.
]]

local getBoundingBox = require("../getBoundingBox")

export type Box = {
	cframe: CFrame, 
	size: vector,
	data: any?
}

export type BvhNode = {
	cframe: CFrame,
	size: vector,
	left: BvhNode?,
	right: BvhNode?,
	data: any?
}

local cfget: (cf: CFrame, prop: string) -> any do
	xpcall(function()
		return (CFrame.identity::any)[""]
	end, function()
		cfget = debug.info(2, "f")
	end)
end

local function traverseBVH(root: BvhNode, callback: (box: BvhNode, stop: () -> ()) -> boolean)
	local stack = {root}
	local stackSize = 1
	local stopFlag = false

	local function stop()
		table.clear(stack)
		stopFlag = true
	end

	while stackSize > 0 do
		local node = table.remove(stack)
		if not node then break end
		stackSize -= 1

		local shouldContinue = callback(node, stop)
		if not shouldContinue then continue end
		if stopFlag then break end

		if node.right then
			stackSize += 1
			stack[stackSize] = node.right
		end

		if node.left then
			stackSize += 1
			stack[stackSize] = node.left
		end
	end
end

local function refitFromChildren(node: BvhNode)
	local left = node.left
	local right = node.right

	if left and right then
		local lp: vector = left.cframe.Position :: any
		local rp: vector = right.cframe.Position :: any

		local minB = vector.create(
			math.min(lp.x - left.size.x * 0.5,  rp.x - right.size.x * 0.5),
			math.min(lp.y - left.size.y * 0.5,  rp.y - right.size.y * 0.5),
			math.min(lp.z - left.size.z * 0.5,  rp.z - right.size.z * 0.5)
		)
		local maxB = vector.create(
			math.max(lp.x + left.size.x * 0.5,  rp.x + right.size.x * 0.5),
			math.max(lp.y + left.size.y * 0.5,  rp.y + right.size.y * 0.5),
			math.max(lp.z + left.size.z * 0.5,  rp.z + right.size.z * 0.5)
		)

		node.size   = maxB - minB
		node.cframe = CFrame.new(((minB + maxB) * 0.5) :: any)
	elseif left then
		node.cframe = left.cframe
		node.size   = left.size
	elseif right then
		node.cframe = right.cframe
		node.size   = right.size
	end
end

local split
local function determine(parent: BvhNode, name: string, boxes: {Box})
	if #boxes > 1 then
		local cframe, size = getBoundingBox(boxes)
		parent[name] = {
			cframe = cframe,
			size = size,
		}

		split(parent[name], boxes)
	elseif #boxes == 1 then
		local box = boxes[1]
		parent[name] = {
			cframe = box.cframe,
			size = box.size,
			data = box.data
		}
	end
end

function split(parent: BvhNode, boxes: {Box})
	local size = parent.size
	local longestAxis

	if size.x >= size.y and size.x >= size.z then
		longestAxis = "X"
	elseif size.y >= size.x and size.y >= size.z then
		longestAxis = "Y"
	else
		longestAxis = "Z"
	end

	table.sort(boxes, function(a, b)
		return cfget(a.cframe, longestAxis) < cfget(b.cframe, longestAxis)
	end)

	local len = #boxes
	local mid = len // 2

	local leftBoxes = table.create(mid)
	local rightBoxes = table.create(len - mid)
	table.move(boxes, 1, mid, 1, leftBoxes)
	table.move(boxes, mid + 1, len, 1, rightBoxes)

	determine(parent, "left", leftBoxes)
	determine(parent, "right", rightBoxes)
end

local function createBVH(boxes: {Box}): (BvhNode)
	if #boxes == 0 then
		return {
			cframe = CFrame.new(0, 0, 0),
			size = vector.create(0, 0, 0)
		}
	end

	local cframe, size = getBoundingBox(boxes)

	local root = {
		cframe = cframe,
		size = size
	}

	split(root, boxes)

	return root
end

local function getWorldAABB(cf: CFrame, size: vector): (vector, vector)
	local hx, hy, hz = size.x / 2, size.y / 2, size.z / 2
	
	local ax = vector.create(math.abs(cf.RightVector.X), math.abs(cf.RightVector.Y), math.abs(cf.RightVector.Z))
	local ay = vector.create(math.abs(cf.UpVector.X),    math.abs(cf.UpVector.Y),    math.abs(cf.UpVector.Z))
	local az = vector.create(math.abs(cf.LookVector.X),  math.abs(cf.LookVector.Y),  math.abs(cf.LookVector.Z))

	local worldHalf = vector.create(
		ax.x * hx + ay.x * hy + az.x * hz,
		ax.y * hx + ay.y * hy + az.y * hz,
		ax.z * hx + ay.z * hy + az.z * hz
	)

	local pos: vector = cf.Position :: any
	return pos - worldHalf, pos + worldHalf
end

local function needsUpdate(oldCFrame: CFrame, oldSize: vector, newBox: Box, threshold: number)
	local distance    = vector.magnitude((oldCFrame.Position - newBox.cframe.Position) :: any)
	local sizeChange  = vector.magnitude(oldSize - newBox.size)
	
	local oldRight: vector = oldCFrame.RightVector :: any
	local newRight: vector = newBox.cframe.RightVector :: any
	local rotationChange = vector.magnitude(oldRight - newRight)  -- 0..2 range

	return distance > threshold or sizeChange > threshold or rotationChange > 0.01
end

local SPLIT_RATIO = 0.001

local function surfaceArea(size: vector): number
	return 2 * (size.x * size.y + size.y * size.z + size.z * size.x)
end

local function collectLeaves(node: BvhNode, out: {Box})
	if node.data then
		table.insert(out, { cframe = node.cframe, size = node.size, data = node.data })
	else
		if node.left then collectLeaves(node.left, out) end
		if node.right then collectLeaves(node.right, out) end
	end
end

local function updateBVHNode(node: BvhNode?, oldBoxes: {Box}, newBoxes: {Box}, threshold: number, splitRatio: number)
	if not node then return false end

	-- Leaf node
	if node.data and node.data.shapeInst then
		-- Find corresponding new box
		local newBox
		for _, box in newBoxes do
			if box.data.shapeInst == node.data.shapeInst then
				newBox = box
				break
			end
		end
		
		if newBox and needsUpdate(node.cframe, node.size, newBox, threshold) then
			node.cframe = newBox.cframe
			node.size = newBox.size
			node.data = newBox.data
			return true
		end
		return false
	end

	-- Internal node
	local leftUpdated = updateBVHNode(node.left, oldBoxes, newBoxes, threshold, splitRatio)
	local rightUpdated = updateBVHNode(node.right, oldBoxes, newBoxes, threshold, splitRatio)

	-- If either child updated, recalculate bounds
	if leftUpdated or rightUpdated then
		-- Get combined bounds of children
		local leftBounds = node.left and {
			cframe = node.left.cframe,
			size = node.left.size,
			--volume = node.left.volume
		}
		local rightBounds = node.right and {
			cframe = node.right.cframe,
			size = node.right.size,
			--volume = node.right.volume
		}

		if leftBounds and rightBounds then
			local lMin, lMax = getWorldAABB(leftBounds.cframe, leftBounds.size)
			local rMin, rMax = getWorldAABB(rightBounds.cframe, rightBounds.size)

			local minBounds = vector.create(
				math.min(lMin.x, rMin.x),
				math.min(lMin.y, rMin.y),
				math.min(lMin.z, rMin.z)
			)
			local maxBounds = vector.create(
				math.max(lMax.x, rMax.x),
				math.max(lMax.y, rMax.y),
				math.max(lMax.z, rMax.z)
			)

			local size   = maxBounds - minBounds
			local center = (minBounds + maxBounds) / 2
			node.cframe  = CFrame.new(center :: any)  -- parent AABB has no rotation
			node.size    = size
		elseif leftBounds then
			local lMin, lMax = getWorldAABB(leftBounds.cframe, leftBounds.size)
			local size   = lMax - lMin
			local center = (lMin + lMax) / 2
			node.cframe  = CFrame.new(center :: any)
			node.size    = size
		elseif rightBounds then
			local rMin, rMax = getWorldAABB(rightBounds.cframe, rightBounds.size)
			local size   = rMax - rMin
			local center = (rMin + rMax) / 2
			node.cframe  = CFrame.new(center :: any)
			node.size    = size
		end
		
		local parentSA = surfaceArea(node.size)
		local leftSA   = node.left  and surfaceArea(node.left.size)  or 0
		local rightSA  = node.right and surfaceArea(node.right.size) or 0

		if parentSA > splitRatio * (leftSA + rightSA) then
			local leaves = {}
			collectLeaves(node, leaves)
			if #leaves > 1 then
				local rebuilt = createBVH(leaves)
				node.cframe = rebuilt.cframe
				node.size   = rebuilt.size
				node.left   = rebuilt.left
				node.right  = rebuilt.right
			end
		end

		return true
	end

	return false
end

local function updateBVH(bvh: BvhNode, oldBoxes: {Box}, newBoxes: {Box}, threshold: number?, splitRatio: number?)
	local threshold = threshold or 0
	local splitRatio = splitRatio or SPLIT_RATIO

	if bvh.size == vector.zero and #newBoxes > 0 then
		local newBVH = createBVH(newBoxes)
		bvh.cframe = newBVH.cframe
		bvh.size = newBVH.size
		bvh.left = newBVH.left
		bvh.right = newBVH.right

		return true, bvh
	end

	local success = updateBVHNode(bvh, oldBoxes, newBoxes, threshold, splitRatio)
	return success, bvh
end

local function visualize(bvh)
	local parts = {}
	traverseBVH(bvh, function(box)
		local part = Instance.new("Part")
		part.Anchored = true
		part.Transparency = 1
		part.CastShadow = false
		part.CFrame = box.cframe
		part.Size = box.size :: any
		part.CanCollide = false
		part.CanQuery = false
		part.Locked = true
		
		local highlight = Instance.new("SelectionBox")
		highlight.SurfaceTransparency = 0.8
		highlight.Adornee = part
		highlight.LineThickness = 0.2
		highlight.Color3 = Color3.fromRGB(0, 0, 0)
		table.insert(parts, part)

		if not box.right and not box.left then
			highlight.Color3 = Color3.fromRGB(255, 0, 0)
		end
		highlight.Parent = part

		return true
	end)
	return parts
end

return {
	createBVH = createBVH,
	traverseBVH = traverseBVH,
	updateBVH = updateBVH,
	getBoundingBox = getBoundingBox,
	visualize = visualize,
}