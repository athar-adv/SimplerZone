--!native
--!optimize 2

--[[
	Cool geometry helper module :)
	Author: athar_adv
]]

local Vertices = require("@self/Vertices")
local Bvh = require("@self/Bvh")
local BoxCylinderIntersection = require("@self/BoxCylinderIntersection")

export type Box = Bvh.Box
export type BvhNode = Bvh.BvhNode

local Geometry = {
	getBoundingBoxFromBoxes = require("./getBoundingBox"),
	Vertices = Vertices,
	Bvh = Bvh,
	BoxCylinderIntersection = BoxCylinderIntersection
}

local dot = vector.dot
local cross = vector.cross
local magn = vector.magnitude

local function tpart(pos: Vector3)
	local part = Instance.new("Part")
	part.Position = pos
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.Size = Vector3.one
	part.Name = "TEST_PART"
	part.Parent = workspace
	return part
end

local function isCollinear(p1: vector, p2: vector, p3: vector, p4: vector)
	local volume = dot(p2 - p1, cross(p3 - p1, p4 - p1))
	return math.abs(volume) < 1e-6 -- Tolerance for floating point comparison
end

local function barycentricinbounds(p: vector, a: vector, b: vector, c: vector)
	local v0 = b - a
	local v1 = c - a
	local v2 = p - a
	
	local d00 = dot(v0, v0)
	local d01 = dot(v0, v1)
	local d11 = dot(v1, v1)
	local d20 = dot(v2, v0)
	local d21 = dot(v2, v1)
	
	local denom = d00 * d11 - d01 * d01
	
	local v = (d11 * d20 - d01 * d21) / denom;
	local w = (d00 * d21 - d01 * d20) / denom;
	local u = 1 - v - w;
	
	return u >= 0 and v >= 0 and u <= 1 and v <= 1 and u + v <= 1
end

local function rayTriangleIntersect(rayOrigin: vector, rayDir: vector, a: vector, b: vector, c: vector, maxT: number): boolean
	local edge1 = b - a
	local edge2 = c - a
	local h = cross(rayDir, edge2)
	local det = dot(edge1, h)

	if math.abs(det) < 1e-10 then
		return false
	end

	local invDet = 1 / det
	local s = rayOrigin - a
	local u = invDet * dot(s, h)

	if u < 0 or u > 1 then
		return false
	end

	local q = cross(s, edge1)
	local v = invDet * dot(rayDir, q)

	if v < 0 or u + v > 1 then
		return false
	end

	local t = invDet * dot(edge2, q)

	return t >= 0 and t <= maxT
end

local function segmentTriangleIntersect(p1: vector, p2: vector, a: vector, b: vector, c: vector): boolean
	local dir = p2 - p1
	local len = magn(dir)
	if len < 1e-10 then
		return false
	end
	return rayTriangleIntersect(p1, dir / len, a, b, c, len)
end

type PointInShapeFunctions = {
	[string]: (point: vector, cframe: CFrame, size: vector) -> boolean
}

local PointInShapeFns: PointInShapeFunctions = {
	Block = function(point, cframe, size)
		return Geometry.isPointInBox(cframe, size, point)
	end,

	Cylinder = function(point, cf, size)
		local pos = cf.Position
		
		local height = size.X
		local radius = size.Y / 2 
		
		local lPoint = cf:PointToObjectSpace(point)
		
		local axisAligned = pos + (cf.XVector.Unit * lPoint.X)
		
		return magn(axisAligned - point) <= radius
	end,

	Ball = function(point, cframe, size)
		local radius = size.x / 2 
		local center = cframe.Position
		
		return magn(point - center) <= radius
	end,

	Wedge = function(point, cf, size)
		local pos = cf.Position

		local s2 = size / 2

		local xvec = cf.XVector.Unit * s2.X
		local yvec = cf.YVector.Unit * s2.Y
		local zvec = cf.ZVector.Unit * s2.Z

		-- Backwards, right, up
		local a = pos + xvec + zvec + yvec
		-- Backwards, right, down
		local b = pos + xvec + zvec - yvec
		-- Forwards, right, down
		local c = pos + xvec - zvec - yvec
		
		point = cf:PointToWorldSpace(cf:PointToObjectSpace(point) * vector.create(0, 1, 1) + vector.create(size.X/2, 0, 0))
		
		return barycentricinbounds(point, a, b, c)
	end,

	CornerWedge = function(point, cf, size)
		local pos = cf.Position

		local s2 = size / 2

		local xvec = cf.XVector.Unit * s2.X
		local yvec = cf.YVector.Unit * s2.Y
		local zvec = cf.ZVector.Unit * s2.Z
		
		-- Top for both
		-- Forwards, right, up
		local a = pos + xvec - zvec + yvec
		
		-- Bottom for both
		-- Forwards, right, down
		local b = pos + xvec - zvec - yvec
		
		local c = pos - xvec - zvec - yvec
		local d = pos + xvec + zvec - yvec
		
		-- This is done to put the point in the plane of the triangles
		local fpoint = cf:PointToWorldSpace(cf:PointToObjectSpace(point) * vector.create(1, 1, 0) - vector.create(0, 0, size.Z/2))
		local spoint = cf:PointToWorldSpace(cf:PointToObjectSpace(point) * vector.create(0, 1, 1) + vector.create(size.X/2, 0, 0))
		
		return barycentricinbounds(fpoint, a, b, c) and barycentricinbounds(spoint, a, b, d)
	end,
}

function Geometry.doBoxesIntersect(boxACframe: CFrame, boxASize: vector, boxBCFrame: CFrame, boxBSize: vector): boolean
	-- Transform boxB into boxA's local space
	local AtoB = boxACframe:ToObjectSpace(boxBCFrame)

	-- Get half sizes
	local boxAHalfSize = boxASize / 2
	local boxBHalfSize = boxBSize / 2

	-- Get the translation vector
	local translation = AtoB.Position

	-- Get the rotation vectors 
	local r = AtoB.RightVector
	local u = AtoB.UpVector
	local l = -AtoB.LookVector  -- Negative because of how Roblox defines LookVector

	-- Test separation along boxA's local axes (X, Y, Z)
	if math.abs(translation.X) > boxAHalfSize.X + 
		boxBHalfSize.X * math.abs(r.X) + 
		boxBHalfSize.Y * math.abs(u.X) + 
		boxBHalfSize.Z * math.abs(l.X) then
		return false
	end

	if math.abs(translation.Y) > boxAHalfSize.Y + 
		boxBHalfSize.X * math.abs(r.Y) + 
		boxBHalfSize.Y * math.abs(u.Y) + 
		boxBHalfSize.Z * math.abs(l.Y) then
		return false
	end

	if math.abs(translation.Z) > boxAHalfSize.Z + 
		boxBHalfSize.X * math.abs(r.Z) + 
		boxBHalfSize.Y * math.abs(u.Z) + 
		boxBHalfSize.Z * math.abs(l.Z) then
		return false
	end

	-- Test separation along boxB's local axes (RightVector, UpVector, LookVector)
	if math.abs(dot(translation, r)) > 
		boxAHalfSize.X * math.abs(r.X) + 
			boxAHalfSize.Y * math.abs(r.Y) + 
			boxAHalfSize.Z * math.abs(r.Z) + 
			boxBHalfSize.X then
		return false
	end

	if math.abs(dot(translation, u)) > 
		boxAHalfSize.X * math.abs(u.X) + 
			boxAHalfSize.Y * math.abs(u.Y) + 
			boxAHalfSize.Z * math.abs(u.Z) + 
			boxBHalfSize.Y then
		return false
	end

	if math.abs(dot(translation, l)) > 
		boxAHalfSize.X * math.abs(l.X) + 
			boxAHalfSize.Y * math.abs(l.Y) + 
			boxAHalfSize.Z * math.abs(l.Z) + 
			boxBHalfSize.Z then
		return false
	end

	-- Test separation along the 9 cross products (edge cross edge)

	-- X axis of boxA crossed with each axis of boxB
	if math.abs(translation.Z * r.Y - translation.Y * r.Z) > 
		boxAHalfSize.Y * math.abs(r.Z) + 
			boxAHalfSize.Z * math.abs(r.Y) + 
			boxBHalfSize.Y * math.abs(l.X) + 
			boxBHalfSize.Z * math.abs(u.X) then
		return false
	end

	if math.abs(translation.Z * u.Y - translation.Y * u.Z) > 
		boxAHalfSize.Y * math.abs(u.Z) + 
			boxAHalfSize.Z * math.abs(u.Y) + 
			boxBHalfSize.X * math.abs(l.X) + 
			boxBHalfSize.Z * math.abs(r.X) then
		return false
	end

	if math.abs(translation.Z * l.Y - translation.Y * l.Z) > 
		boxAHalfSize.Y * math.abs(l.Z) + 
			boxAHalfSize.Z * math.abs(l.Y) + 
			boxBHalfSize.X * math.abs(u.X) + 
			boxBHalfSize.Y * math.abs(r.X) then
		return false
	end

	-- Y axis of boxA crossed with each axis of boxB
	if math.abs(translation.X * r.Z - translation.Z * r.X) > 
		boxAHalfSize.X * math.abs(r.Z) + 
			boxAHalfSize.Z * math.abs(r.X) + 
			boxBHalfSize.Y * math.abs(l.Y) + 
			boxBHalfSize.Z * math.abs(u.Y) then
		return false
	end

	if math.abs(translation.X * u.Z - translation.Z * u.X) > 
		boxAHalfSize.X * math.abs(u.Z) + 
			boxAHalfSize.Z * math.abs(u.X) + 
			boxBHalfSize.X * math.abs(l.Y) + 
			boxBHalfSize.Z * math.abs(r.Y) then
		return false
	end

	if math.abs(translation.X * l.Z - translation.Z * l.X) > 
		boxAHalfSize.X * math.abs(l.Z) + 
			boxAHalfSize.Z * math.abs(l.X) + 
			boxBHalfSize.X * math.abs(u.Y) + 
			boxBHalfSize.Y * math.abs(r.Y) then
		return false
	end

	-- Z axis of boxA crossed with each axis of boxB
	if math.abs(translation.Y * r.X - translation.X * r.Y) > 
		boxAHalfSize.X * math.abs(r.Y) + 
			boxAHalfSize.Y * math.abs(r.X) + 
			boxBHalfSize.Y * math.abs(l.Z) + 
			boxBHalfSize.Z * math.abs(u.Z) then
		return false
	end

	if math.abs(translation.Y * u.X - translation.X * u.Y) > 
		boxAHalfSize.X * math.abs(u.Y) + 
			boxAHalfSize.Y * math.abs(u.X) + 
			boxBHalfSize.X * math.abs(l.Z) + 
			boxBHalfSize.Z * math.abs(r.Z) then
		return false
	end

	if math.abs(translation.Y * l.X - translation.X * l.Y) > 
		boxAHalfSize.X * math.abs(l.Y) + 
			boxAHalfSize.Y * math.abs(l.X) + 
			boxBHalfSize.X * math.abs(u.Z) + 
			boxBHalfSize.Y * math.abs(r.Z) then
		return false
	end

	-- If no separating axis was found, the boxes intersect
	return true
end

function Geometry.doesBoxIntersectSphere(
	spherePos: vector,
	radius: number,
	boxCFrame: CFrame,
	boxSize: vector
): boolean
	local localSpherePos = boxCFrame:PointToObjectSpace(spherePos)
	local boxHalfSize = boxSize/2
	local closestPoint = Vector3.new(
		math.clamp(localSpherePos.X, -boxHalfSize.X, boxHalfSize.X),
		math.clamp(localSpherePos.Y, -boxHalfSize.Y, boxHalfSize.Y),
		math.clamp(localSpherePos.Z, -boxHalfSize.Z, boxHalfSize.Z)
	)
	
	local distance = magn(localSpherePos - closestPoint)
	return distance <= radius
end

function Geometry.doesBoxIntersectWedge(
	boxCFrame: CFrame,
	boxSize: vector,
	wedgeCFrame: CFrame,
	wedgeSize: vector
): boolean
	local dot = vector.dot
	local cross = vector.cross
	local magnitude = vector.magnitude

	local boxHalfSize = boxSize / 2
	local wedgeHalfSize = wedgeSize / 2

	local wedgeXVec = wedgeCFrame.XVector * wedgeHalfSize.X
	local wedgeYVec = wedgeCFrame.YVector * wedgeHalfSize.Y
	local wedgeZVec = wedgeCFrame.ZVector * wedgeHalfSize.Z

	local wedgeTriVerts = {
		wedgeCFrame.Position + wedgeXVec + wedgeZVec + wedgeYVec,
		wedgeCFrame.Position + wedgeXVec + wedgeZVec - wedgeYVec,
		wedgeCFrame.Position + wedgeXVec - wedgeZVec - wedgeYVec,
	}

	local boxXVec = boxCFrame.XVector * boxHalfSize.X
	local boxYVec = boxCFrame.YVector * boxHalfSize.Y
	local boxZVec = boxCFrame.ZVector * boxHalfSize.Z

	local boxCorners = {
		boxCFrame.Position + boxXVec + boxYVec + boxZVec,
		boxCFrame.Position + boxXVec + boxYVec - boxZVec,
		boxCFrame.Position + boxXVec - boxYVec + boxZVec,
		boxCFrame.Position + boxXVec - boxYVec - boxZVec,
		boxCFrame.Position - boxXVec + boxYVec + boxZVec,
		boxCFrame.Position - boxXVec + boxYVec - boxZVec,
		boxCFrame.Position - boxXVec - boxYVec + boxZVec,
		boxCFrame.Position - boxXVec - boxYVec - boxZVec,
	}

	for _, corner in boxCorners do
		local projectedPoint = wedgeCFrame:PointToWorldSpace(
			wedgeCFrame:PointToObjectSpace(corner) * vector.create(0, 1, 1) 
				+ vector.create(wedgeSize.X / 2, 0, 0)
		)

		if barycentricinbounds(projectedPoint, wedgeTriVerts[1], wedgeTriVerts[2], wedgeTriVerts[3]) then
			local localPoint = wedgeCFrame:PointToObjectSpace(corner)
			if math.abs(localPoint.X) <= wedgeHalfSize.X 
				and math.abs(localPoint.Y) <= wedgeHalfSize.Y 
				and math.abs(localPoint.Z) <= wedgeHalfSize.Z then
				return true
			end
		end
	end

	local wedgeCorners = {
		wedgeCFrame.Position + wedgeXVec + wedgeZVec + wedgeYVec,
		wedgeCFrame.Position + wedgeXVec + wedgeZVec - wedgeYVec,
		wedgeCFrame.Position + wedgeXVec - wedgeZVec - wedgeYVec,
		wedgeCFrame.Position - wedgeXVec + wedgeZVec + wedgeYVec,
		wedgeCFrame.Position - wedgeXVec + wedgeZVec - wedgeYVec,
		wedgeCFrame.Position - wedgeXVec - wedgeZVec - wedgeYVec,
	}

	for _, corner in wedgeCorners do
		local localPoint = boxCFrame:PointToObjectSpace(corner)
		if math.abs(localPoint.X) <= boxHalfSize.X 
			and math.abs(localPoint.Y) <= boxHalfSize.Y 
			and math.abs(localPoint.Z) <= boxHalfSize.Z then
			return true
		end
	end

	local boxEdges = {
		{boxCorners[1], boxCorners[2]}, {boxCorners[1], boxCorners[3]}, {boxCorners[1], boxCorners[5]},
		{boxCorners[2], boxCorners[4]}, {boxCorners[2], boxCorners[6]},
		{boxCorners[3], boxCorners[4]}, {boxCorners[3], boxCorners[7]},
		{boxCorners[4], boxCorners[8]},
		{boxCorners[5], boxCorners[6]}, {boxCorners[5], boxCorners[7]},
		{boxCorners[6], boxCorners[8]},
		{boxCorners[7], boxCorners[8]},
	}

	for _, edge in boxEdges do
		if segmentTriangleIntersect(edge[1], edge[2], wedgeTriVerts[1], wedgeTriVerts[2], wedgeTriVerts[3]) then
			return true
		end
	end

	return false
end

function Geometry.isPointInShape(point: vector, shape: "Cylinder" | "Block" | "Ball" | "Wedge" | "CornerWedge", cframe: CFrame, size: vector)
	local shapecheck = PointInShapeFns[shape]
	if not shapecheck then
		error(`Shape check function not found for {shape}`)
	end

	return shapecheck(point, cframe, size)
end

function Geometry.getBoundingBox(points: {vector}): (CFrame, vector)
	if #points == 0 then
		error("The points array cannot be empty.")
	end

	-- Initialize min and max with the first point
	local minX, minY, minZ = points[1].X, points[1].Y, points[1].Z
	local maxX, maxY, maxZ = points[1].X, points[1].Y, points[1].Z

	for _, point in points do
		minX = math.min(minX, point.X)
		minY = math.min(minY, point.Y)
		minZ = math.min(minZ, point.Z)

		maxX = math.max(maxX, point.X)
		maxY = math.max(maxY, point.Y)
		maxZ = math.max(maxZ, point.Z)
	end
	
	local center = vector.create(
		(minX + maxX) / 2,
		(minY + maxY) / 2,
		(minZ + maxZ) / 2
	)
	
	local size = vector.create(
		maxX - minX,
		maxY - minY,
		maxZ - minZ
	)
	
	return CFrame.new(center), size
end

function Geometry.getRandomPointInSimplex(RANDOM_POINT_DIMENSION, points: {vector}, transform: CFrame)
	if #points < 2 then
		error("Not enough points to form a simplex.")
	end

	local selectedVertices = {}
	local indices = {}
	local weights = {}
	local totalWeight = 0

	while #selectedVertices < RANDOM_POINT_DIMENSION + 1 do
		local index = math.random(1, #points)
		if indices[index] then continue end

		local point: vector = transform:PointToWorldSpace(points[index]) :: any
		selectedVertices[#selectedVertices + 1] = point
		indices[index] = true

		-- Generate and accumulate random weight
		local weight = math.random()
		weights[#weights + 1] = weight
		totalWeight += weight
	end

	-- Compute the random point as a weighted sum of the selected points
	local randomPoint = vector.zero
	for i = 1, RANDOM_POINT_DIMENSION + 1 do
		randomPoint = randomPoint + selectedVertices[i] * (weights[i] / totalWeight)
	end

	return randomPoint
end

function Geometry.isPointInTetrahedron(p: vector, a: vector, b: vector, c: vector, d: vector)
	local pa = p - a
	local pb = p - b

	local ca = c - a
	local ba = b - a
	local da = d - a
	local cb = c - b
	local db = d - b

	local n1 = cross(ba, ca)
	local n2 = cross(ba, da)
	local n3 = cross(ca, da)
	local n4 = cross(cb, db)

	local g = (a + b + c + d) / 4

	local ga = g - a
	local gb = g - b

	local alpha1 = dot(ga, n1)
	local alpha2 = dot(ga, n2)
	local alpha3 = dot(ga, n3)
	local alpha4 = dot(gb, n4)

	if alpha1 > 0 then
		n1 = -n1
	end
	if alpha2 > 0 then
		n2 = -n2
	end
	if alpha3 > 0 then
		n3 = -n3
	end
	if alpha4 > 0 then
		n4 = -n4
	end

	-- Compute dot products for the point p with the normals
	local beta1 = dot(pa, n1)
	local beta2 = dot(pa, n2)
	local beta3 = dot(pa, n3)
	local beta4 = dot(pb, n4)

	return beta1 < 0 and beta2 < 0 and beta3 < 0 and beta4 < 0
end

function Geometry.generateTetrahedrons(points)
	local tetrahedrons = {}
	
	-- Use the first point as a reference to create tetrahedrons
	local basePoint = points[1]
	for i = 2, #points - 2 do
		for j = i + 1, #points - 1 do
			for k = j + 1, #points do
				local a, b, c = points[i], points[j], points[k]

				if isCollinear(basePoint, a, b, c) then
					continue
				end

				table.insert(tetrahedrons, { basePoint, a, b, c })
			end
		end
	end

	return tetrahedrons
end

function Geometry.getBoxesVerticesForParts(Vertices, parts: {Part})
	local boxes = {}
	local points = {}
	local partToPointIndex = {}

	for _, part in parts do
		if not part:IsA("Part") then
			error("PartsZone.new() must be fed a pure array of parts.")
		end

		local shape = part.Shape.Name
		local vget = Vertices[shape]

		if not vget then
			error(`Shape {shape} could not be converted into points.`)
		end

		local vgroup = vget(part)
		
		table.insert(points, vgroup)
		table.insert(partToPointIndex, part)

		table.insert(boxes, {
			cframe = part.CFrame,
			size = part.ExtentsSize,
			part = part,
		})
	end

	return boxes, points, partToPointIndex
end

function Geometry.isPointInBox(cframe: CFrame, size: vector, point: vector)
	local halfSize = size / 2
	local localPoint = cframe:PointToObjectSpace(point)

	local withinX = math.abs(localPoint.X) <= halfSize.X
	local withinY = math.abs(localPoint.Y) <= halfSize.Y
	local withinZ = math.abs(localPoint.Z) <= halfSize.Z
	
	return withinX and withinY and withinZ
end

local function isPointInBoxWithHalfSize(point, boxCFrame, halfSize)
	local localPoint = boxCFrame:PointToObjectSpace(point)

	return math.abs(localPoint.X) <= halfSize.X and
		math.abs(localPoint.Y) <= halfSize.Y and
		math.abs(localPoint.Z) <= halfSize.Z
end

function Geometry.areAnyItemPointsInBox(world: {Instance}, boxCFrame: CFrame, boxSize: vector): boolean
	local halfSize = boxSize/2

	for _, item in world do
		if not isPointInBoxWithHalfSize(item.Position, boxCFrame, halfSize) then continue end

		return true
	end
	return false
end

return Geometry