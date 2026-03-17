local RunService = game:GetService("RunService")

local success, isEdit = pcall(function()
	return RunService:IsEdit()
end)

if not success or isEdit == false then
	local world = Instance.new("WorldModel")
	world.Name = "SimpleZone2World"
	world.Parent = game.ReplicatedStorage

	return world
end
return nil