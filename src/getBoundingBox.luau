return function(boxes, VOXEL_SIZE)
	local VOXEL_SIZE = VOXEL_SIZE or 0
	local minBounds = vector.create(math.huge, math.huge, math.huge)
	local maxBounds = vector.create(-math.huge, -math.huge, -math.huge)

	for _, box in boxes do
		local cframe, size = box.cframe, box.size
		local halfSize = size * 0.5

		-- Calculate the eight corners of the box, PROPERLY ROTATED by the CFrame
		local offsets = {
			vector.create(-halfSize.x, -halfSize.y, -halfSize.z),
			vector.create(halfSize.x, -halfSize.y, -halfSize.z),
			vector.create(-halfSize.x, halfSize.y, -halfSize.z),
			vector.create(halfSize.x, halfSize.y, -halfSize.z),
			vector.create(-halfSize.x, -halfSize.y, halfSize.z),
			vector.create(halfSize.x, -halfSize.y, halfSize.z),
			vector.create(-halfSize.x, halfSize.y, halfSize.z),
			vector.create(halfSize.x, halfSize.y, halfSize.z),
		}

		local corners = {}
		for i, offset in offsets do
			corners[i] = cframe:PointToWorldSpace(offset :: any) :: any
		end

		-- Expand the bounding box to include this box's corners
		if VOXEL_SIZE > 0 then
			for _, corner in corners do
				minBounds = vector.create(
					math.min(minBounds.x, corner.x) // VOXEL_SIZE * VOXEL_SIZE,
					math.min(minBounds.y, corner.y) // VOXEL_SIZE * VOXEL_SIZE,
					math.min(minBounds.z, corner.z) // VOXEL_SIZE * VOXEL_SIZE
				)
				maxBounds = vector.create(
					math.max(maxBounds.x, corner.x) // VOXEL_SIZE * VOXEL_SIZE,
					math.max(maxBounds.y, corner.y) // VOXEL_SIZE * VOXEL_SIZE,
					math.max(maxBounds.z, corner.z) // VOXEL_SIZE * VOXEL_SIZE
				)
			end
		else
			for _, corner in corners do
				minBounds = vector.create(
					math.min(minBounds.x, corner.x),
					math.min(minBounds.y, corner.y),
					math.min(minBounds.z, corner.z)
				)
				maxBounds = vector.create(
					math.max(maxBounds.x, corner.x),
					math.max(maxBounds.y, corner.y),
					math.max(maxBounds.z, corner.z)
				)
			end
		end
	end

	-- Calculate the bounding box center and size
	local size = maxBounds - minBounds
	local center = (minBounds + maxBounds) / 2
	local boundingCFrame = CFrame.new(center::any)

	-- Return the CFrame and size
	return boundingCFrame, size
end