--!strict

local Types = require("./Types")
type Shape = Types.Shape
type BoxShape = Types.BoxShape
type CylinderShape = Types.CylinderShape
type SphereShape = Types.SphereShape
type MeshShape = Types.MeshShape
type GroupShape = Types.GroupShape
type WedgeShape = Types.WedgeShape

local Serializer = {}

local function indent(level: number): string
	return string.rep("\t", level)
end

local function num(n: number): string
	if n == math.huge then
		return "math.huge"
	elseif n == -math.huge then
		return "-math.huge"
	elseif n ~= n then
		return "0/0"
	end
	return string.format("%.17g", n)
end

local function vec(v: vector): string
	return string.format("vector.create(%s, %s, %s)", num(v.x), num(v.y), num(v.z))
end

local function cf(c: CFrame): string
	local comps = { c:GetComponents() }
	local parts = table.create(#comps)

	for i = 1, #comps do
		parts[i] = num(comps[i])
	end

	return "CFrame.new(" .. table.concat(parts, ", ") .. ")"
end

local function meshToCode(mesh: MeshPart, level: number): string
	local lines = {}

	table.insert(lines, "(function()")
	table.insert(lines, indent(level + 1) .. "local AssetService = game:GetService(\"AssetService\")")
	table.insert(lines, indent(level + 1) .. string.format(
		"local part = AssetService:CreateMeshPartAsync(%q)",
		mesh.MeshId
		))
	table.insert(lines, indent(level + 1) .. "part.CFrame = CFrame.identity")
	table.insert(lines, indent(level + 1) .. "return part")
	table.insert(lines, indent(level) .. "end)()")

	return table.concat(lines, "\n")
end

local serializeValue
local serializeShape

serializeValue = function(value: any, level: number): string
	local t = typeof(value)

	if t == "number" then
		return num(value)

	elseif t == "string" then
		return string.format("%q", value)

	elseif t == "boolean" then
		return tostring(value)

	elseif t == "Vector3" then
		return vec(value)

	elseif t == "CFrame" then
		return cf(value)

	elseif t == "table" then
		-- IMPORTANT: detect shape tables
		if value.ty ~= nil then
			return serializeShape(value :: Shape, level)
		end

		-- array fallback
		local lines = {}
		table.insert(lines, "{")
		for _, v in ipairs(value) do
			table.insert(lines, indent(level + 1) .. serializeValue(v, level + 1)::any .. ",")
		end
		table.insert(lines, indent(level) .. "}")
		return table.concat(lines, "\n")

	else
		error("Unsupported type: " .. t)
	end
end

serializeShape = function(shape: Shape, level: number): string
	local lines = {}
	table.insert(lines, "{")

	-- Always write ty first
	table.insert(lines, indent(level + 1) .. 'ty = "' .. shape.ty .. '",')

	if shape.ty == "Box" then
		local s = shape :: BoxShape
		table.insert(lines, indent(level + 1) .. "cframe = " .. cf(s.cframe) .. ",")
		table.insert(lines, indent(level + 1) .. "size = " .. vec(s.size) .. ",")

	elseif shape.ty == "Cylinder" then
		local s = shape :: CylinderShape
		table.insert(lines, indent(level + 1) .. "center = " .. vec(s.center) .. ",")
		table.insert(lines, indent(level + 1) .. "axis = " .. vec(s.axis) .. ",")
		table.insert(lines, indent(level + 1) .. "radius = " .. num(s.radius) .. ",")
		table.insert(lines, indent(level + 1) .. "cframe = " .. cf(s.cframe) .. ",")
		table.insert(lines, indent(level + 1) .. "size = " .. vec(s.size) .. ",")

	elseif shape.ty == "Sphere" then
		local s = shape :: SphereShape
		table.insert(lines, indent(level + 1) .. "center = " .. vec(s.center) .. ",")
		table.insert(lines, indent(level + 1) .. "radius = " .. num(s.radius) .. ",")
		--table.insert(lines, indent(level + 1) .. "vertices = " .. serializeValue(s.vertices, level + 1) .. ",")

	elseif shape.ty == "Wedge" then
		local s = shape :: WedgeShape
		table.insert(lines, indent(level + 1) .. "cframe = " .. cf(s.cframe) .. ",")
		table.insert(lines, indent(level + 1) .. "size = " .. vec(s.size) .. ",")
		table.insert(lines, indent(level + 1) .. "vertices = " .. serializeValue(s.vertices, level + 1) .. ",")

	elseif shape.ty == "Group" then
		local s = shape :: GroupShape
		table.insert(lines, indent(level + 1) .. "cframe = " .. cf(s.cframe) .. ",")
		table.insert(lines, indent(level + 1) .. "shapes = {")
		for _, child in ipairs(s.shapes) do
			table.insert(lines, indent(level + 2) .. serializeShape(child, level + 2) .. ",")
		end
		table.insert(lines, indent(level + 1) .. "},")

	elseif shape.ty == "Mesh" then
		local s = shape :: MeshShape
		table.insert(lines, indent(level + 1) .. "cframe = " .. cf(s.cframe) .. ",")
		table.insert(lines, indent(level + 1) .. "size = " .. vec(s.size) .. ",")
		table.insert(lines, indent(level + 1) .. "mesh = " .. meshToCode(s.mesh, level + 1) .. ",")

	else
		error("Unknown shape type: " .. tostring(shape.ty))
	end

	table.insert(lines, indent(level) .. "}")
	return table.concat(lines, "\n")
end

function Serializer.serialize(shape: Shape): string
	return "-- Generated ZShape\nreturn " .. serializeShape(shape, 0)
end

return Serializer
