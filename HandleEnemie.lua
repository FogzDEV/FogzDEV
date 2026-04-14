--Services and variables
local serverStorage = game:GetService("ServerStorage")
local runService = game:GetService("RunService")
local Players = game:GetService("Players")
local configs = serverStorage.Configs
local infoZombies = require(configs.ConfigZombies)
local MAXUPDATETIME = 0.5

--Params
local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Include
raycastParams.FilterDescendantsInstances = {workspace.Map} -- Only raycast on map

local overlapParams = OverlapParams.new()
overlapParams.FilterType = Enum.RaycastFilterType.Exclude
overlapParams.FilterDescendantsInstances = {workspace.Enemies}

--Colors For Zombie
local ZombieColors = {
	[1] = Color3.new(0.05, 0.7, 0.3),
	[2] = Color3.new(0.5, 0.9, 0.4),
	[3] = Color3.new(0.1, 0.3, 0.2),
	[4] = Color3.new(0.6, 0.2, 0.2),
	[5] = Color3.new(0.2, 0.1, 0.6),
}

local ZombieAI = {}
ZombieAI.__index = ZombieAI

--Tables for zombies and players
local AliveZombies = {}
local AlivePlayers = {} -- To avoid calling GetPlayers() all the time

function ZombieAI:Raycast() --ray cast to check if there is a wall between zombie and player
	local origin = self.PrimaryPart.Position + Vector3.new(0, -1.5, 0)
	local direction = (self.TargetPosition - origin).Unit -- direction to the player
	
	local raycastResult = workspace:Raycast(origin, direction * 5, raycastParams)
	
	if not raycastResult then return end
	
	return true -- if true then there is a wall
end

function ZombieAI:Death() -- ragdoll system
	self.Humanoid.Died:Once(function()
		local function CreateAttachment(part, CFrame)
			local attachment = Instance.new("Attachment")
			attachment.Parent = part
			attachment.CFrame = CFrame
			return attachment
		end
		
		local function CreateSocket(part, c0, c1)
			local ballSocket = Instance.new("BallSocketConstraint")
			ballSocket.Attachment0 = CreateAttachment(self.Model.Torso, c0)
			ballSocket.Attachment1 = CreateAttachment(part, c1)
			ballSocket.LimitsEnabled = true
			ballSocket.Parent = self.Model.Torso
		end
		
		for _, v in self.Model.Torso:GetChildren() do
			if v:IsA("Motor6D") and v.Name ~= "Neck" then
				CreateSocket(v.Part1, v.C0, v.C1)
				v:Destroy()
			end
		end
		
		game.Debris:AddItem(self.Model, 5)
	end)
end

function ZombieAI:Damaged()
	self.Humanoid.HealthChanged:Connect(function(health)
		if health < self.CurrentHealth then
			self.Animations["Damaged"]:Play()
		end
		self.CurrentHealth = health
	end)
end

function ZombieAI:SetupAnimations() -- setup animations and state animations
	for _, anim in script.Animations:GetChildren() do
		local track = self.Humanoid:FindFirstChildOfClass("Animator"):LoadAnimation(anim)
		self.Animations[anim.Name] = track
	end
	
	self.Humanoid.StateChanged:Connect(function(old, new)
		if not self.Animations[new.Name] then return end
		self.Animations[new.Name]:Play()
		if self.Animations[old.Name] then
			self.Animations[old.Name]:Stop()
		end
	end)
end

function ZombieAI:Setup() -- Setup zombie Infos: Health, WalkSpeed, Damage and Colors
	self.Humanoid.MaxHealth = self.Info.Health
	self.Humanoid.Health = self.Info.Health
	self.Humanoid.WalkSpeed = self.Info.Speed	
	self.Humanoid.BreakJointsOnDeath = false
	self.Humanoid.RequiresNeck = false
	
	local bodyColors = self.Model:FindFirstChildOfClass("BodyColors")
	local color = ZombieColors[math.random(1, #ZombieColors)]

	for i,v in ipairs({"Head","LeftArm","RightArm"}) do -- A for loop with parts that I want to change the color of
		bodyColors[v.."Color3"] = color
	end
	
	self:SetupAnimations()
	self:Death()
	self:Damaged()
	
	table.insert(AliveZombies, self)
end

function ZombieAI:FindTarget() -- Find the closest player and set target
	local NearestTarget
	local NearestDistance = math.huge
	local NearestPos 
	
	for _, plr in ipairs(AlivePlayers) do
		local char = plr.Character
		if not char then continue end
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if not hrp then continue end
		local hum = char:FindFirstChildOfClass("Humanoid")
		local plrDistance = (hrp.Position - self.PrimaryPart.Position).Magnitude
		if hum and hum.Health > 0 and plrDistance < NearestDistance then
			NearestTarget = plr
			NearestDistance = plrDistance
			local offset = 5 * (plrDistance / 10) -- to avoid pathfinding and add some variation to the movement, making it walk slightly to the sides
			NearestPos = hrp.Position + Vector3.new(math.random(-offset, offset), 0, math.random(-offset, offset)) -- random offset
		end
	end
	
	if NearestTarget then
		self.Target = NearestTarget
		self.TargetPosition = NearestPos
		self.Distance = NearestDistance
		self:MoveToTarget()
	end
end

function ZombieAI:Attack() -- Damage player
	if os.clock() - self.LastAttack <= 1 then
		return
	end
	
	self.LastAttack = os.clock() -- update debounce
	
	local Origin = self.PrimaryPart.CFrame
	local parts = workspace:GetPartBoundsInBox(Origin, Vector3.new(10, 10, 10), overlapParams) -- hitbox
	
	local victins = {} -- save the players that already got hit
	
	for _, part in parts do -- hit box parts
		local Vhumanoid = part.Parent:FindFirstChildOfClass("Humanoid")
		if not Vhumanoid or Vhumanoid.Health <= 0 or victins[Vhumanoid] then continue end
		Vhumanoid:TakeDamage(5)
		victins[Vhumanoid] = true
	end
	
	self.Animations["Attack"]:Play()
end

function ZombieAI:MoveToTarget() -- Move to Target
	self.Humanoid:MoveTo(self.TargetPosition)
	local needJump = self:Raycast() -- check if need jump
	if needJump then
		self.Humanoid.Jump = true -- jump if raycast hit something
	end
	
	if self.Distance <= 5 then -- Attack Check
		self:Attack()
	end
end

function ZombieAI.New(zombie) -- Setup Zombie MetaTable
	local ZombieInfo = setmetatable({}, ZombieAI)
	ZombieInfo.Model = zombie
	ZombieInfo.PrimaryPart = zombie.PrimaryPart
	ZombieInfo.Info = infoZombies[zombie.Name] -- get all zombie infos (like health, speed, etc)
	ZombieInfo.Humanoid = zombie:FindFirstChildOfClass("Humanoid")
	ZombieInfo.LastPathUpdate = os.clock()
	ZombieInfo.LastAttack = os.clock()
	ZombieInfo.CurrentHealth = zombie.Humanoid.Health
	ZombieInfo.Animations = {}
	
	ZombieInfo:Setup()
	
	return ZombieInfo
end

runService.Heartbeat:Connect(function()
	for i = #AliveZombies, 1, -1 do
		local zombie = AliveZombies[i]
		if not zombie.Model or zombie.Humanoid.Health <= 0 then
			table.remove(AliveZombies, i) -- clear zombie if not exist or dead
			continue
		end

		if os.clock() - zombie.LastPathUpdate >= MAXUPDATETIME then -- debounce
			zombie:FindTarget()
			zombie.LastPathUpdate = os.clock() -- update last path update
		end
	end
end)

--Setup Players
game.Players.PlayerAdded:Connect(function(plr)
	plr.CharacterAdded:Connect(function(char)
		table.insert(AlivePlayers, plr)
	end)
end)

game.Players.PlayerRemoving:Connect(function(plr)
	table.remove(AlivePlayers, table.find(AlivePlayers, plr))
end)

return ZombieAI
