--!strict
--!native
--!optimize 2

export type CylinderGeom = {
	center: vector,
	direction: vector,
	height: number,
	radius: number
}
export type BoxGeom = {
	center: vector,
	extent: vector
}

local keyMap = { "X", "Y", "Z" }

local function ComputeOrthonormalBasis(v0: vector): (vector, vector)
	local v1

	if math.abs(v0.x) > math.abs(v0.y) then
		v1 = vector.create(-v0.z, 0, v0.x)
	else
		v1 = vector.create(0, v0.z, -v0.y)
	end

	v1 = vector.normalize(v1)

	local v2 = vector.normalize(vector.cross(v0, v1))

	return v1, v2
end

local function ComputeSqrDistance(P0: vector, P1: vector, C: vector, W0: vector, W1: vector): number
	local P0mC = P0 - C
	local P1mC = P1 - C

	local Q0 = vector.create(
		vector.dot(W0, P0mC),
		vector.dot(W1, P0mC)
	)

	local Q1 = vector.create(
		vector.dot(W0, P1mC),
		vector.dot(W1, P1mC)
	)

	local direction = Q1 - Q0
	local s = direction.x * Q1.x + direction.y * Q1.y

	if s <= 0 then
		return Q1.x * Q1.x + Q1.y * Q1.y
	else
		s = direction.x * Q0.x + direction.y * Q0.y

		if s >= 0 then
			return Q0.x * Q0.x + Q0.y * Q0.y
		else
			s = s / (direction.x * direction.x + direction.y * direction.y)

			local closest = Q0 + s * direction

			return closest.x * closest.x + closest.y * closest.y
		end
	end
end

local function Intersects0(C: vector, D: vector, r: number, hDiv2: number, E: vector): boolean
	local negEmCDivD = {
		(-E.x - C.x) / D.x,
		(-E.y - C.y) / D.y,
		(-E.z - C.z) / D.z
	}

	local posEmCDivD = {
		(E.x - C.x) / D.x,
		(E.y - C.y) / D.y,
		(E.z - C.z) / D.z
	}

	local lower = math.max(math.max(negEmCDivD[1], negEmCDivD[2]), math.max(negEmCDivD[3], -hDiv2))
	local upper = math.min(math.min(posEmCDivD[1], posEmCDivD[2]), math.min(posEmCDivD[3], hDiv2))

	if lower <= upper then
		return true
	end

	local sqrRadius = r * r

	local dotDC = vector.dot(D, C)

	local d0e0 = D.x * E.x
	local d1e1 = D.y * E.y
	local d2e2 = D.z * E.z

	local t1 = d0e0 - d1e1 - d2e2 - dotDC
	local s1p = t1 + hDiv2
	local s1n = t1 - hDiv2

	local t2 = -d0e0 + d1e1 - d2e2 - dotDC
	local s2p = t2 + hDiv2
	local s2n = t2 - hDiv2

	local t3 = d0e0 + d1e1 - d2e2 - dotDC
	local s3p = t3 + hDiv2
	local s3n = t3 - hDiv2

	local t4 = -d0e0 - d1e1 + d2e2 - dotDC
	local s4p = t4 + hDiv2
	local s4n = t4 - hDiv2

	local t5 = d0e0 - d1e1 + d2e2 - dotDC
	local s5p = t5 + hDiv2
	local s5n = t5 - hDiv2

	local t6 = -d0e0 + d1e1 + d2e2 - dotDC
	local s6p = t6 + hDiv2
	local s6n = t6 - hDiv2

	local W0, W1 = ComputeOrthonormalBasis(D)
	local sqrDistance
	local P0, P1

	lower = s1p >= 0 and -E.z or (-E.z - s1p / D.z)
	upper = s5n <= 0 and E.z or (E.z - s5n / D.z)

	if lower <= upper then
		P0 = vector.create(E.x, -E.y, lower)
		P1 = vector.create(E.x, -E.y, upper)

		sqrDistance = ComputeSqrDistance(P0, P1, C, W0, W1)

		if sqrDistance <= sqrRadius then
			return true
		end
	end

	lower = s2p >= 0 and -E.z or (-E.z - s2p / D.z)
	upper = s6n <= 0 and E.z or (E.z - s6n / D.z)

	if lower <= upper then
		P0 = vector.create(-E.x, E.y, lower)
		P1 = vector.create(-E.x, E.y, upper)

		sqrDistance = ComputeSqrDistance(P0, P1, C, W0, W1)

		if sqrDistance <= sqrRadius then
			return true
		end
	end

	lower = s1p >= 0 and -E.y or (-E.y - s1p / D.y)
	upper = s3n <= 0 and E.y or (E.y - s3n / D.y)

	if lower <= upper then
		P0 = vector.create(E.x, lower, -E.z)
		P1 = vector.create(E.x, upper, -E.z)

		sqrDistance = ComputeSqrDistance(P0, P1, C, W0, W1)

		if sqrDistance <= sqrRadius then
			return true
		end
	end

	lower = s4p >= 0 and -E.y or (-E.y - s4p / D.y)
	upper = s6n <= 0 and E.y or (E.y - s6n / D.y)

	if lower <= upper then
		P0 = vector.create(-E.x, lower, E.z)
		P1 = vector.create(-E.x, upper, E.z)

		sqrDistance = ComputeSqrDistance(P0, P1, C, W0, W1)

		if sqrDistance <= sqrRadius then
			return true
		end
	end

	lower = s2p >= 0 and -E.x or (-E.x - s2p / D.x)
	upper = s3n <= 0 and E.x or (E.x - s3n / D.x)

	if lower <= upper then
		P0 = vector.create(lower, E.y, -E.z)
		P1 = vector.create(upper, E.y, -E.z)

		sqrDistance = ComputeSqrDistance(P0, P1, C, W0, W1)

		if sqrDistance <= sqrRadius then
			return true
		end
	end

	lower = s4p >= 0 and -E.x or (-E.x - s4p / D.x)
	upper = s5n <= 0 and E.x or (E.x - s5n / D.x)

	if lower <= upper then
		P0 = vector.create(lower, -E.y, E.z)
		P1 = vector.create(upper, -E.y, E.z)

		sqrDistance = ComputeSqrDistance(P0, P1, C, W0, W1)

		if sqrDistance <= sqrRadius then
			return true
		end
	end

	lower = s3p >= 0 and -E.z or (-E.z - s3p / D.z)
	upper = s5p <= 0 and E.z or (E.z - s5p / D.z)

	if lower <= upper then
		if s3p >= 0 then
			P0 = vector.create(E.x, E.y - s3p / D.y, -E.z)
		else
			P0 = vector.create(E.x, E.y, -E.z - s3p / D.z)
		end

		if s5p <= 0 then
			P1 = vector.create(E.x, -E.y - s5p / D.y, E.z)
		else
			P1 = vector.create(E.x, -E.y, E.z - s5p / D.z)
		end

		sqrDistance = ComputeSqrDistance(P0, P1, C, W0, W1)

		if sqrDistance <= sqrRadius then
			return true
		end
	end

	lower = s2n >= 0 and -E.z or (-E.z - s2n / D.z)
	upper = s4n <= 0 and E.z or (E.z - s4n / D.z)

	if lower <= upper then
		if s2n >= 0 then
			P0 = vector.create(-E.x, E.y - s2n / D.y, -E.z)
		else
			P0 = vector.create(-E.x, E.y, -E.z - s2n / D.z)
		end

		if s4n <= 0 then
			P1 = vector.create(-E.x, -E.y - s4n / D.y, E.z)
		else
			P1 = vector.create(-E.x, -E.y, E.z - s4n / D.z)
		end

		sqrDistance = ComputeSqrDistance(P0, P1, C, W0, W1)

		if sqrDistance <= sqrRadius then
			return true
		end
	end

	lower = s6p >= 0 and -E.x or (-E.x - s6p / D.x)
	upper = s3p <= 0 and E.x or (E.x - s3p / D.x)

	if lower <= upper then
		if s6p >= 0 then
			P0 = vector.create(-E.x, E.y, E.z - s6p / D.z)
		else
			P0 = vector.create(-E.x - s6p / D.x, E.y, E.z)
		end

		if s3p <= 0 then
			P1 = vector.create(E.x, E.y, -E.z - s3p / D.z)
		else
			P1 = vector.create(E.x - s3p / D.x, E.y, -E.z)
		end

		sqrDistance = ComputeSqrDistance(P0, P1, C, W0, W1)

		if sqrDistance <= sqrRadius then
			return true
		end
	end

	lower = s4n >= 0 and -E.x or (-E.x - s4n / D.x)
	upper = s1n <= 0 and E.x or (E.x - s1n / D.x)

	if lower <= upper then
		if s4n >= 0 then
			P0 = vector.create(-E.x, -E.y, E.z - s4n / D.z)
		else
			P0 = vector.create(-E.x - s4n / D.x, -E.y, E.z)
		end

		if s1n <= 0 then
			P1 = vector.create(E.x, -E.y, -E.z - s1n / D.z)
		else
			P1 = vector.create(E.x - s1n / D.x, -E.y, -E.z)
		end

		sqrDistance = ComputeSqrDistance(P0, P1, C, W0, W1)

		if sqrDistance <= sqrRadius then
			return true
		end
	end

	lower = s5p >= 0 and -E.y or (-E.y - s5p / D.y)
	upper = s6p <= 0 and E.y or (E.y - s6p / D.y)

	if lower <= upper then
		if s5p >= 0 then
			P0 = vector.create(E.x - s5p / D.x, -E.y, E.z)
		else
			P0 = vector.create(E.x, -E.y - s5p / D.y, E.z)
		end

		if s6p <= 0 then
			P1 = vector.create(-E.x - s6p / D.x, E.y, E.z)
		else
			P1 = vector.create(-E.x, E.y - s6p / D.y, E.z)
		end

		sqrDistance = ComputeSqrDistance(P0, P1, C, W0, W1)

		if sqrDistance <= sqrRadius then
			return true
		end
	end

	lower = s1n >= 0 and -E.y or (-E.y - s1n / D.y)
	upper = s2n <= 0 and E.y or (E.y - s2n / D.y)

	if lower <= upper then
		if s1n >= 0 then
			P0 = vector.create(E.x - s1n / D.x, -E.y, -E.z)
		else
			P0 = vector.create(E.x, -E.y - s1n / D.y, -E.z)
		end

		if s2n <= 0 then
			P1 = vector.create(-E.x - s2n / D.x, E.y, -E.z)
		else
			P1 = vector.create(-E.x, E.y - s2n / D.y, -E.z)
		end

		sqrDistance = ComputeSqrDistance(P0, P1, C, W0, W1)

		if sqrDistance <= sqrRadius then
			return true
		end
	end

	return false
end

local function BoxIsOutsideCylinderSlab(box: BoxGeom, cylinder: CylinderGeom): boolean
	local C = cylinder.center
	local D = cylinder.direction
	local h = cylinder.height
	local E = box.extent

	local absD = vector.create(math.abs(D.x), math.abs(D.y), math.abs(D.z))
	local p = vector.dot(absD, E)
	local gamma = -vector.dot(D, C)

	return math.abs(gamma) > p + h / 2
end

local function Intersects2(i: vector, C: vector, r: number, E: vector): boolean
	local absC1, absC2
	if i.y == 1 then
		absC1 = math.abs(C.x)
	elseif i.y == 2 then
		absC1 = math.abs(C.y)
	elseif i.y == 3 then
		absC1 = math.abs(C.z)
	end
	if i.z == 1 then
		absC2 = math.abs(C.x)
	elseif i.z == 2 then
		absC2 = math.abs(C.y)
	elseif i.z == 3 then
		absC2 = math.abs(C.z)
	end

	local E1, E2
	if i.y == 1 then
		E1 = math.abs(E.x)
	elseif i.y == 2 then
		E1 = math.abs(E.y)
	elseif i.y == 3 then
		E1 = math.abs(E.z)
	end
	if i.z == 1 then
		E2 = math.abs(E.x)
	elseif i.z == 2 then
		E2 = math.abs(E.y)
	elseif i.z == 3 then
		E2 = math.abs(E.z)
	end
	if absC1 <= E1 and absC2 <= E2 then
		return true
	end

	local sqrDistance = 0
	local delta = absC1 - E1

	if delta > 0 then
		sqrDistance = sqrDistance + delta * delta
	end

	delta = absC2 - E2

	if delta > 0 then
		sqrDistance = sqrDistance + delta * delta
	end

	return sqrDistance <= r * r
end

local function Intersects1(i: vector, C: vector, D: vector, r: number, hDiv2: number, E: vector): boolean
	local c0, c1, c2, d0, d1, e0, e1, e2
	if i.x == 1 then
		c0 = C.x
		d0 = D.x
		e0 = E.x
	elseif i.x == 2 then
		c0 = C.y
		d0 = D.y
		e0 = E.y
	elseif i.x == 3 then
		c0 = C.z
		d0 = D.z
		e0 = E.z
	end
	if i.y == 1 then
		c1 = C.x
		d1 = D.x
		e1 = E.x
	elseif i.y == 2 then
		c1 = C.y
		d1 = D.y
		e1 = E.y
	elseif i.y == 3 then
		c1 = C.z
		d1 = D.z
		e1 = E.z
	end
	if i.z == 1 then
		c2 = C.x
		e2 = E.x
	elseif i.z == 2 then
		c2 = C.y
		e2 = E.y
	elseif i.z == 3 then
		c2 = C.z
		e2 = E.z
	end

	local e0pc0 = e0 + c0
	local e0mc0 = e0 - c0
	local e1pc1 = e1 + c1
	local e1mc1 = e1 - c1

	local absC2 = math.abs(c2)

	if absC2 <= e2 then
		local negEmCDivD = {-e0pc0 / d0, -e1pc1 / d1}
		local posEmCDivD = {e0mc0 / d0, e1mc1 / d1}

		local lower = math.max(math.max(negEmCDivD[1], negEmCDivD[2]), -hDiv2)
		local upper = math.min(math.min(posEmCDivD[1], posEmCDivD[2]), hDiv2)

		if lower <= upper then
			return true
		end
	end

	local sMin = 0
	local tHat = d1 * e1mc1 - d0 * e0pc0

	if -hDiv2 <= tHat then
		if tHat <= hDiv2 then
			sMin = -(d0 * e1mc1 + d1 * e0pc0)
		else 
			sMin = -(e1pc1 + d0 * hDiv2) / d1
		end
	else
		sMin = -(e1mc1 + d1 * hDiv2) / d0
	end

	local sMax = 0
	local tBar = d0 * e0mc0 - d1 * e1pc1

	if -hDiv2 <= tBar then
		if tBar <= hDiv2 then
			sMax = d0 * e1pc1 + d1 * e0mc0
		else 
			sMax = (e1pc1 + d1 * hDiv2) / d0
		end
	else 
		sMax = (e0mc0 + d0 * hDiv2) / d1
	end

	local sqrDistance = 0

	if 0 < sMin then
		sqrDistance = sqrDistance + sMin * sMin
	elseif sMax < 0 then
		sqrDistance = sqrDistance + sMax * sMax
	end

	local delta = absC2 - e2

	if delta > 0 then
		sqrDistance = sqrDistance + delta * delta
	end

	return sqrDistance <= r * r
end

local function TestIntersectionQuery(box: BoxGeom, cylinder: CylinderGeom): boolean
	if BoxIsOutsideCylinderSlab(box, cylinder) then
		return false
	end

	local C = cylinder.center
	local D = cylinder.direction
	local r = cylinder.radius

	local hDiv2 = cylinder.height / 2
	local E = box.extent

	if D.x < 0 then
		C = vector.create(-C.x, C.y, C.z)
		D = vector.create(-D.x, D.y, D.z)
	end

	if D.y < 0 then
		C = vector.create(C.x, -C.y, C.z)
		D = vector.create(D.x, -D.y, D.z)
	end

	if D.z < 0 then
		C = vector.create(C.x, C.y, -C.z)
		D = vector.create(D.x, D.y, -D.z)
	end

	if D.x > 0 then
		if D.y > 0 then
			if D.z > 0 then 
				return Intersects0(C, D, r, hDiv2, E)
			else 
				return Intersects1(vector.create(1, 2, 3), C, D, r, hDiv2, E)
			end
		else
			if D.z > 0 then 
				return Intersects1(vector.create(3, 1, 2), C, D, r, hDiv2, E)
			else 
				return Intersects2(vector.create(1, 2, 3), C, r, E)
			end
		end
	else
		if D.y > 0 then
			if D.z > 0 then
				return Intersects1(vector.create(2, 3, 1), C, D, r, hDiv2, E)
			else 
				return Intersects2(vector.create(2, 3, 1), C, r, E)
			end
		else
			if D.z > 0 then
				return Intersects2(vector.create(3, 1, 2), C, r, E)
			else 
				return false
			end
		end
	end
end

local function GetCylinderGeometry(cylinderPart: BasePart, boxCf: CFrame): CylinderGeom
	local relativeCF = boxCf:Inverse() * cylinderPart.CFrame

	local center = relativeCF.Position
	local height = cylinderPart.ExtentsSize.X
	local direction = relativeCF.XVector

	local radius = cylinderPart.ExtentsSize.Y / 2

	return {
		center = center,
		direction = direction,
		height = height,
		radius = radius,
	} :: any
end

local function GetBoxGeometry(size: vector): BoxGeom
	return {
		center = Vector3.zero,
		extent = size / 2,
	} :: any
end

local function PublicTestIntersectionQuery(box: BasePart, cyl: BasePart)
	local cylGeom = GetCylinderGeometry(cyl, box.CFrame)
	local boxGeom = GetBoxGeometry(box.ExtentsSize::any)
	return TestIntersectionQuery(boxGeom, cylGeom)
end

return {
	queryUsingParts = PublicTestIntersectionQuery,
	queryUsingGeoms = TestIntersectionQuery,
	getCylinderGeometry = GetCylinderGeometry,
	getBoxGeometry = GetBoxGeometry,
	getCylinderGeometryNoPart = function(cylCf: CFrame, cylSize: vector, boxCf: CFrame): CylinderGeom
		local relativeCF = boxCf:Inverse() * cylCf
		
		local center = relativeCF.Position
		local height = cylSize.x
		local direction = relativeCF.RightVector
		
		local radius = cylSize.y / 2

		return {
			center = center,
			direction = direction,
			height = height,
			radius = radius,
		} :: any
	end,
}