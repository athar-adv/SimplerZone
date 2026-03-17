--!optimize 2
--!native

return {
	Block = function(size: vector)
		local s2 = size / 2

		local a = vector.create(s2.X, s2.Y, s2.Z)
		local b = vector.create(s2.X, s2.Y, -s2.Z)
		local c = vector.create(s2.X, -s2.Y, s2.Z)
		local d = vector.create(s2.X, -s2.Y, -s2.Z)
		local e = vector.create(-s2.X, s2.Y, s2.Z)
		local f = vector.create(-s2.X, s2.Y, -s2.Z)
		local g = vector.create(-s2.X, -s2.Y, s2.Z)
		local h = vector.create(-s2.X, -s2.Y, -s2.Z)

		return {a, b, c, d, e, f, g, h}
	end,

	Wedge = function(size: vector)
		local s2 = size / 2

		local a = vector.create(s2.X, s2.Y, s2.Z)
		local b = vector.create(-s2.X, s2.Y, s2.Z)
		local c = vector.create(s2.X, -s2.Y, s2.Z)
		local d = vector.create(-s2.X, -s2.Y, s2.Z)
		local e = vector.create(s2.X, -s2.Y, -s2.Z)
		local f = vector.create(-s2.X, -s2.Y, -s2.Z)

		return {a, b, c, d, e, f}
	end,

	CornerWedge = function(size: vector)
		local s2 = size / 2

		local a = vector.create(s2.X, s2.Y, -s2.Z)
		local b = vector.create(s2.X, -s2.Y, -s2.Z)
		local c = vector.create(-s2.X, -s2.Y, -s2.Z)
		local d = vector.create(s2.X, -s2.Y, s2.Z)
		local e = vector.create(-s2.X, -s2.Y, s2.Z)

		return {a, b, c, d, e}
	end,

	Cylinder = function(size: vector)
		local height = size.X
		local radius = size.Y / 2

		local topCenter = vector.create(height / 2, 0, 0)
		local bottomCenter = vector.create(-height / 2, 0, 0)

		local numVertices = 8

		local vertices = {}

		for i = 0, numVertices - 1 do
			local angle = (i / numVertices) * math.pi * 2
			local y = math.cos(angle) * radius
			local z = math.sin(angle) * radius
			local topVertex = topCenter + vector.create(0, y, z)
			table.insert(vertices, topVertex)
		end

		for i = 0, numVertices - 1 do
			local angle = (i / numVertices) * math.pi * 2
			local y = math.cos(angle) * radius
			local z = math.sin(angle) * radius
			local bottomVertex = bottomCenter + vector.create(0, y, z)
			table.insert(vertices, bottomVertex)
		end

		return vertices
	end,

	Ball = function(size: vector)
		local radius = size.X / 2

		local numSlices = 8
		local numStacks = 4

		local vertices = {}

		for stack = 0, numStacks do
			local phi = math.pi * (stack / numStacks)
			local y = math.cos(phi) * radius
			local ringRadius = math.sin(phi) * radius

			for slice = 0, numSlices - 1 do
				local theta = 2 * math.pi * (slice / numSlices)
				local x = math.cos(theta) * ringRadius
				local z = math.sin(theta) * ringRadius

				local vertex = vector.create(x, y, z)
				table.insert(vertices, vertex)
			end
		end

		return vertices
	end,
}