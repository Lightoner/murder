
AddCSLuaFile( "cl_init.lua" )
AddCSLuaFile( "shared.lua" )
include('shared.lua')

local ENT_KILL_DELAY = 10

function ENT:Initialize()
	self:SetModel("models/weapons/w_knife_t.mdl")

	self:PhysicsInit( SOLID_VPHYSICS )
	-- self:PhysicsInitSphere(50)
	self:SetMoveType( MOVETYPE_VPHYSICS )
	self:SetSolid( SOLID_VPHYSICS )
	self:DrawShadow(false)

	// don't do impact damage
	-- self:SetTrigger(true)
	-- self:SetCollisionGroup(COLLISION_GROUP_WEAPON)

	local phys = self:GetPhysicsObject()
	if IsValid(phys) then
		phys:Wake()
	end

	self.FireKillTime = CurTime() + ENT_KILL_DELAY

	self.HitSomething = false
end

function ENT:CreateTimerKnifeWeapon()
	if self.TimerKnifeWeaponCreated then return end

	if !IsValid(self) || self:IsMarkedForDeletion() then return end
	if !IsValid(self.Owner) || !self.Owner:IsPlayer() then return end

	local knife = ents.Create("weapon_mu_knife")
	knife.TimerKnife = true
	knife.TimerKnifeOwner = self.Owner
	knife.DisallowPickUpEnd = self.DisallowPickUpEnd

	self.TimerKnifeWeaponCreated = true
end

hook.Add("Think", "TimerKnivesThink", function()
	for k, knife in ipairs(ents.FindByClass("weapon_mu_knife")) do
		if IsValid(knife) && !knife:IsMarkedForDeletion() && knife.TimerKnife then
			if IsValid(knife.TimerKnifeOwner) then
				if knife.DisallowPickUpEnd == nil || knife.DisallowPickUpEnd < CurTime() then
					if knife.TimerKnifeOwner:Alive() then
						knife.TimerKnifeOwner:Give("weapon_mu_knife")
						knife:Remove()
					end
				end
			else
				knife:Remove()
			end
		end
	end
end)

function ENT:Think()
	if self.FireKillTime != nil && self.FireKillTime <= CurTime() then
		self.FireKillTime = nil
		self:CreateTimerKnifeWeapon()
		self:Fire("kill", "")
	end
	if self.RemoveNext && IsValid(self) then
		self.RemoveNext = false
		self:CreateTimerKnifeWeapon()
		self:Remove()
	end
	if self.HitSomething then
		self.HitSomething = false
		self:CreateTimerKnifeWeapon()
		self:Remove()
	end

	self:NextThink(CurTime())
	return true
end

local function addangle(ang,ang2)
	ang:RotateAroundAxis(ang:Up(),ang2.y) -- yaw
	ang:RotateAroundAxis(ang:Forward(),ang2.r) -- roll
	ang:RotateAroundAxis(ang:Right(),ang2.p) -- pitch
end

function ENT:PhysicsCollide( data, physobj )
	-- print(data.OurOldVelocity:Length())

	if self.HitSomething then return end
	if self.RemoveNext then return end
	
	local ply = data.HitEntity
	if IsValid(ply) && ply:IsPlayer() then

		-- self.RemoveNext = true
		-- self:SetColor(Color(0,0,0,0))

		local dmg = DamageInfo()
		dmg:SetDamage(120)
		dmg:SetAttacker(self:GetOwner())
		dmg:SetInflictor(self)
		ply:TakeDamageInfo(dmg)
		self:EmitSound("physics/flesh/flesh_squishy_impact_hard" .. math.random(1, 4) .. ".wav")

		local pos = ply:GetPos() + Vector(00,0,40)
		local ang = ply:GetAngles() * 1
		addangle(ang, Angle(-60,0,0))

		timer.Simple(0, function ()
			local rag = ply:GetRagdollEntity()

			if IsValid(rag) then
				local pos, ang = rag:GetBonePosition(0)
				local vec = Vector(0, 16, -14)
				vec:Rotate(ang)
				pos = pos + vec
				addangle(ang, Angle(30, -90, 0))

				-- local knife = ents.Create("prop_physics")
				-- knife:SetModel("models/weapons/w_knife_t.mdl")
				-- knife:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
				-- knife:SetPos(pos)
				-- knife:SetAngles(ang)
				-- knife:Spawn()

				-- local phys = knife:GetPhysicsObject()
				-- if IsValid(phys) then
				-- 	phys:EnableCollisions(false)
				-- end


				-- constraint.Weld(rag, knife, 0, 0, 0, true)

				-- rag:CallOnRemove("knife_cleanup", function() SafeRemoveEntity(knife) end)

			end

		end)
	end

	self.HitSomething = true
end

