--!native

--[[
	Cool geometry helper module :)
	Author: athar_adv
]]

local Bvh = require("@self/Bvh")
local BoxCylinderIntersection = require("@self/BoxCylinderIntersection")

export type Box = Bvh.Box
export type BvhNode = Bvh.BvhNode

local Geometry = {
	getBoundingBoxFromBoxes = require("./getBoundingBox"),
	Bvh = Bvh,
	BoxCylinderIntersection = BoxCylinderIntersection
}

local dot = vector.dot
local cross = vector.cross
local magn = vector.magnitude

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

function Geometry.isPointInTri(p: vector, a: vector, b: vector, c: vector)
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

		if Geometry.isPointInTri(projectedPoint, wedgeTriVerts[1], wedgeTriVerts[2], wedgeTriVerts[3]) then
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

return Geometry