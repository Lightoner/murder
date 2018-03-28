local PlayerMeta = FindMetaTable("Player")

util.AddNetworkString("your_are_a_murderer")

GM.MurdererWeight = CreateConVar("mu_murder_weight_multiplier", 2, bit.bor(FCVAR_NOTIFY), "Multiplier for the weight of the murderer chance" )

function PlayerMeta:SetMurderer(bool)
	self.Murderer = bool
	if bool then
		self.MurdererChance = 1
	end
	net.Start( "your_are_a_murderer" )
	net.WriteUInt(bool and 1 or 0, 8)
	net.Send( self )
end

function PlayerMeta:GetMurderer(bool)
	return self.Murderer
end

function PlayerMeta:SetMurdererRevealed(bool)
	self:SetNWBool("MurdererFog", bool)
	if bool then
		if !self.MurdererRevealed then
		end
	else
		if self.MurdererRevealed then
		end
	end
	self.MurdererRevealed = bool
end

function PlayerMeta:GetMurdererRevealed()
	return self.MurdererRevealed
end

function GM:MurdererThink()

end