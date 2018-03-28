local PlayerMeta = FindMetaTable("Player")
local EntityMeta = FindMetaTable("Entity")

function EntityMeta:GetPlayerColor()
	return self:GetNWVector("playerColor") or Vector()
end

function EntityMeta:GetBystanderName()
	local name = self:GetNWString("bystanderName")
	if !name || name == "" then
		return "Bystander" 
	end
	return name
end