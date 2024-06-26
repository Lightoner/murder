// add cs lua all the cl_ or sh_ files
local folders = {
	(GM or GAMEMODE).Folder:sub(11) .. "/gamemode/"
}
for k, folder in pairs(folders) do
	local files, subfolders = file.Find(folder .. "*", "LUA")
	for k, filename in pairs(files) do
		if filename:sub(1, 3) == "cl_" || filename:sub(1, 3) == "sh_" || filename == "shared.lua"
			|| folder:match("/sh_") || folder:match("/cl_") then
			AddCSLuaFile(folder .. filename)
		end
	end
	for k, subfolder in pairs(subfolders) do
		table.insert(folders, folder .. subfolder .. "/")
	end
end

include("sh_translate.lua")
include("shared.lua")
include("weightedrandom.lua")
include("sv_player.lua")
include("sv_spectate.lua")
include("sv_spawns.lua")
include("sv_ragdoll.lua")
include("sv_respawn.lua")
include("sv_murderer.lua")
include("sv_rounds.lua")
include("sv_chattext.lua")
include("sv_loot.lua")
include("sv_bystandername.lua")
include("sv_adminpanel.lua")
include("sv_flashlight.lua")

GM.MurdererFogTime = CreateConVar("mu_murderer_fogtime", 60 * 4, bit.bor(FCVAR_NOTIFY), "Time (in seconds) it takes for a Murderer to show fog for no kills, 0 to disable" )
GM.LocalChat = CreateConVar("mu_localchat", 0, bit.bor(FCVAR_NOTIFY), "Local chat, when enabled only nearby players can hear other players" )
GM.LocalChatRange = CreateConVar("mu_localchat_range", 550, bit.bor(FCVAR_NOTIFY), "The range at which you can hear other players" )
GM.CanDisguise = CreateConVar("mu_disguise", 1, bit.bor(FCVAR_NOTIFY), "Whether the murderer can disguise as dead players" )
GM.RemoveDisguiseOnKill = CreateConVar("mu_disguise_removeonkill", 1, bit.bor(FCVAR_NOTIFY), "Remove the murderer's disguise when he kills someone" )
GM.AFKMoveToSpec = CreateConVar("mu_moveafktospectator", 1, bit.bor(FCVAR_NOTIFY), "Should we move AFK players to spectator on round end" )
GM.RoundLimit = CreateConVar("mu_roundlimit", 30, bit.bor(FCVAR_NOTIFY), "Number of rounds we should play before map change" )
GM.DelayAfterEnoughPlayers = CreateConVar("mu_delay_after_enough_players", 10, bit.bor(FCVAR_NOTIFY), "Time (in seconds) we should wait to start the round after enough players have joined" )
GM.FlashlightBattery = CreateConVar("mu_flashlight_battery", 10, bit.bor(FCVAR_NOTIFY), "How long the flashlight should last in seconds (0 for infinite)" )
GM.Language = CreateConVar("mu_language", "", bit.bor(FCVAR_NOTIFY), "The language Murder should use" )

// replicated
GM.ShowAdminsOnScoreboard = CreateConVar("mu_scoreboard_show_admins", 1, bit.bor(0), "Should show admins on scoreboard" )
GM.AdminPanelAllowed = CreateConVar("mu_allow_admin_panel", 1, bit.bor(FCVAR_NOTIFY), "Should allow admins to use mu_admin_panel" )
GM.ShowSpectateInfo = CreateConVar("mu_show_spectate_info", 1, bit.bor(FCVAR_NOTIFY), "Should show players name and color to spectators" )

GM.AFKTimeMax = CreateConVar("mu_afk_time_max", 60, bit.bor(FCVAR_NOTIFY), "AFK time max" )

function GM:Initialize() 
	self:LoadSpawns()
	self.DeathRagdolls = {}
	self:StartNewRound()
	self:LoadLootData()
	self:LoadMapList()
	self:LoadBystanderNames()
end

function GM:InitPostEntity() 
	local canAdd = self:CountLootItems() <= 0
	for k, ent in pairs(ents.FindByClass("mu_loot")) do
		if canAdd then
			self:AddLootItem(ent)
		end
	end
	self:InitPostEntityAndMapCleanup()
end

function GM:InitPostEntityAndMapCleanup() 
	for k, ent in pairs(ents.GetAll()) do
		if ent:IsWeapon() || ent:GetClass():match("^weapon_") then
			ent:Remove()
		end

		if ent:GetClass():match("^item_") then
			ent:Remove()
		end
	end

	for k, ent in pairs(ents.FindByClass("mu_loot")) do
		ent:Remove()
	end
	-- self:SpawnLoot()
end

function GM:Think()
	self:RoundThink()
	self:MurdererThink()
	self:LootThink()
	self:FlashlightThink()

	for k, ply in pairs(player.GetAll()) do
		if ply:IsCSpectating() && IsValid(ply:GetCSpectatee()) && (!ply.LastSpectatePosSet || ply.LastSpectatePosSet < CurTime()) then
			ply.LastSpectatePosSet = CurTime() + 0.25
			ply:SetPos(ply:GetCSpectatee():GetPos())
		end
		if ply:IsBot() || ply:KeyDown(IN_FORWARD) || ply:KeyDown(IN_JUMP) || ply:KeyDown(IN_ATTACK) || ply:KeyDown(IN_ATTACK2)
			|| ply:KeyDown(IN_MOVELEFT) || ply:KeyDown(IN_MOVERIGHT) || ply:KeyDown(IN_BACK) || ply:KeyDown(IN_DUCK) then
			ply.HasMoved = true
			if ply.HasMovedTime then
				ply.HasMovedTime = CurTime()
			end
		end
		if ply.HasMovedTime && ply.HasMovedTime + math.max(self.AFKTimeMax:GetInt(), 0) < CurTime() then
			ply.AFK = true
			ply:Ignite(math.huge)
		elseif ply.AFK then
			ply.AFK = false
			ply:Extinguish()
		end
	end
end

function GM:AllowPlayerPickup( ply, ent )
	if IsValid(ent) && (ent:GetClass() == "weapon_mu_magnum" || ent:GetClass() == "weapon_mu_knife") then
		return false
	end
	return true
end

function GM:PlayerNoClip( ply )
	return ply:IsListenServerHost() || ply:GetMoveType() == MOVETYPE_NOCLIP
end

function GM:OnEndRound()
end

function GM:OnStartRound()
end

function GM:SendMessageAll(msg) 
	for k,v in pairs(player.GetAll()) do
		v:ChatPrint(msg)
	end
end

function GM:EntityTakeDamage( ent, dmginfo )
	// disable all prop damage
	if IsValid(dmginfo:GetAttacker()) && (dmginfo:GetAttacker():GetClass() == "prop_physics" || dmginfo:GetAttacker():GetClass() == "prop_physics_multiplayer" || dmginfo:GetAttacker():GetClass() == "prop_physics_respawnable" || dmginfo:GetAttacker():GetClass() == "func_physbox") then
		return true
	end

	if IsValid(dmginfo:GetInflictor()) && (dmginfo:GetInflictor():GetClass() == "prop_physics" || dmginfo:GetInflictor():GetClass() == "prop_physics_multiplayer" || dmginfo:GetInflictor():GetClass() == "prop_physics_respawnable" || dmginfo:GetInflictor():GetClass() == "func_physbox") then
		return true
	end
	
	if self.RoundStage == 1 && self.SpawnProtectionActive == true && IsValid(ent) && ent:IsPlayer() && IsValid(dmginfo:GetAttacker()) && dmginfo:GetAttacker():IsPlayer() then
		return true
	end
	
	if IsValid(ent) && ent:IsPlayer() && IsValid(dmginfo:GetAttacker()) && dmginfo:GetAttacker():IsPlayer() && !ent:GetMurderer() && !dmginfo:GetAttacker():GetMurderer() && self.SpecialRoundStage != 2 then
		dmginfo:GetAttacker():Kill()
		local col = dmginfo:GetAttacker():GetPlayerColor()
		local msgs = Translator:AdvVarTranslate(translate.tryTeamKill, {
			player = {text = dmginfo:GetAttacker():Nick() .. ", " .. dmginfo:GetAttacker():GetBystanderName(), color = Color(col.x * 255, col.y * 255, col.z * 255)}
		})
		local ct = ChatText()
		ct:AddParts(msgs)
		ct:SendAll()
		return true
	end
	
	if self.SpecialRoundStage == 1 && IsValid(ent) && ent:IsPlayer() && IsValid(dmginfo:GetInflictor()) && dmginfo:GetInflictor():IsWeapon() && dmginfo:GetInflictor():GetClass() == "weapon_mu_knife" then
		return true
	end

end

function file.ReadDataAndContent(path)
	local f = file.Read(path, "DATA")
	if f then return f end
	f = file.Read("data_static/" .. path, "GAME")
	return f
end

util.AddNetworkString("reopen_round_board")
function GM:ShowTeam(ply) // F2
	net.Start("reopen_round_board")
	net.Send(ply)
end

concommand.Add("mu_version", function (ply)
	if IsValid(ply) then
		ply:ChatPrint("Murder by Mechanical Mind version " .. tostring(GAMEMODE.Version or "error"))
	else
		print("Murder by Mechanical Mind version " .. tostring(GAMEMODE.Version or "error"))
	end
end)

function GM:MaxDeathRagdolls()
	return 20
end