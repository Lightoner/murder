
util.AddNetworkString("SetRound")
util.AddNetworkString("DeclareWinner")

GM.RoundTimeMax = CreateConVar("mu_round_time_max", 600, bit.bor(FCVAR_NOTIFY), "Round time max" )
GM.SpecialRoundCountdownStart = CreateConVar("mu_special_round_countdown_start", 4, bit.bor(FCVAR_NOTIFY), "Special round countdown start" )
GM.SpawnProtection = CreateConVar("mu_spawn_protection", 10, bit.bor(FCVAR_NOTIFY), "Spawn protection" )

GM.RoundStage = 0
GM.RoundCount = 0
GM.SpecialRoundCountdown = math.max(GM.SpecialRoundCountdownStart:GetInt(), 0)
GM.SpecialRoundStage = 0
GM.SpecialRoundForce = 0
GM.SpawnProtectionActive = false
if GAMEMODE then
	GM.RoundStage = GAMEMODE.RoundStage
	GM.RoundCount = GAMEMODE.RoundCount
	
end

function GM:GetRound()
	return self.RoundStage or 0
end

function GM:SetRound(round)
	self.RoundStage = round
	self.RoundTime = CurTime()

	self.RoundSettings = {}

	self.RoundSettings.ShowAdminsOnScoreboard = self.ShowAdminsOnScoreboard:GetBool()
	self.RoundSettings.AdminPanelAllowed = self.AdminPanelAllowed:GetBool()
	self.RoundSettings.ShowSpectateInfo = self.ShowSpectateInfo:GetBool()

	self:NetworkRound()
end

function GM:NetworkRound(ply)
	net.Start("SetRound")
	net.WriteUInt(self.RoundStage, 8)
	net.WriteDouble(self.RoundTime)

	if self.RoundSettings then
		net.WriteUInt(1, 8)
		net.WriteUInt(self.RoundSettings.ShowAdminsOnScoreboard and 1 or 0, 8)
		net.WriteUInt(self.RoundSettings.AdminPanelAllowed and 1 or 0, 8)
		net.WriteUInt(self.RoundSettings.ShowSpectateInfo and 1 or 0, 8)
	else
		net.WriteUInt(0, 8)
	end

	if self.RoundStage == 5 then
		net.WriteDouble(self.StartNewRoundTime)
	end
	
	if self.RoundStage == 1 then
		net.WriteDouble(self.RoundStartTime)
		net.WriteUInt(self.CurrentRoundTimeMax, 32)
		net.WriteDouble(self.SpawnProtectionStartTime)
		net.WriteUInt(self.CurrentSpawnProtection, 32)
	end
	
	net.WriteUInt(self.SpecialRoundCountdown, 32)
	net.WriteUInt(self.SpecialRoundStage, 8)

	if ply == nil then
		net.Broadcast()
	else
		net.Send(ply)
	end
end


function GM:RoundThink()
	local players = team.GetPlayers(2)
	if self.RoundStage == self.Round.NotEnoughPlayers then
		if #players > 1 && (!self.LastPlayerSpawn || self.LastPlayerSpawn + 1 < CurTime()) then 
			self.StartNewRoundTime = CurTime() + self.DelayAfterEnoughPlayers:GetFloat()
			self:SetRound(self.Round.RoundStarting)
		end
	elseif self.RoundStage == self.Round.Playing then
		if self.SpawnProtectionActive == true && self.SpawnProtectionStartTime + self.CurrentSpawnProtection < CurTime() then
			for k, ply in pairs(players) do
				if ply:GetMaterial() == "models/wireframe" then
					ply:SetMaterial("")
				end
			end
			self.SpawnProtectionActive = false
		end
	
		if !self.RoundLastDeath || self.RoundLastDeath < CurTime() then
			self:RoundCheckForWin()
		end
		if self.RoundUnFreezePlayers && self.RoundUnFreezePlayers < CurTime() then
			self.RoundUnFreezePlayers = nil
			for k, ply in pairs(players) do
				if ply:Alive() then
					ply:Freeze(false)
					ply.Frozen = false
				end
			end
		end
		
		if self.SpecialRoundStage != 1 then
			// after x minutes without a kill reveal the murderer
			local time = self.MurdererFogTime:GetFloat()
			time = math.max(0, time)

			if time > 0 && self.MurdererLastKill && self.MurdererLastKill + time < CurTime() then
				local murderer
				local players = team.GetPlayers(2)
				for k,v in pairs(players) do
					if v:GetMurderer() then
						murderer = v
					end
				end
				if murderer && !murderer:GetMurdererRevealed() then
					murderer:SetMurdererRevealed(true)
					self.MurdererLastKill = nil
				end
			end
		end

	elseif self.RoundStage == self.Round.RoundEnd then
		if self.RoundTime + 5 < CurTime() then
			self:StartNewRound()
		end

	elseif self.RoundStage == self.Round.RoundStarting then
		if #players <= 1 then
			self:SetRound(0)
		elseif CurTime() >= self.StartNewRoundTime then
			self:StartNewRound()
		end
	end	
end

function GM:RoundCheckForWin()
	local murderer
	local players = team.GetPlayers(2)
	if #players <= 0 then 
		self.SpecialRoundStage = 0
		self:SetRound(0)
		return 
	end
	
	if self.SpecialRoundStage == 0 then
		local survivors = {}
		for k,v in pairs(players) do
			if v:Alive() && !v:GetMurderer() then
				table.insert(survivors, v)
			end
			if v:GetMurderer() then
				murderer = v
			end
		end

		// check we have a murderer
		if !IsValid(murderer) then
			self:EndTheRound(3, murderer)
			return
		end

		// has the murderer killed everyone?
		if #survivors < 1 then
			self:EndTheRound(1, murderer)
			return
		end

		// is the murderer dead?
		if !murderer:Alive() then
			self:EndTheRound(2, murderer)
			return
		end
		
		// round time ended
		if self.RoundStartTime + self.CurrentRoundTimeMax < CurTime() then
			self:EndTheRound(2, murderer)
			return
		end
	elseif self.SpecialRoundStage == 1 then
		local survivors = {}
		for k,v in pairs(players) do
			if v:Alive() then
				table.insert(survivors, v)
			end
		end
		if #survivors == 1 then 
			self:EndTheRound(1, survivors[1])
			return
		elseif #survivors == 0 then
			self:EndTheRound(3, nil)
			return
		end
		
		// round time ended
		if self.RoundStartTime + self.CurrentRoundTimeMax < CurTime() then
			self:EndTheRound(3, nil)
			return
		end
	elseif self.SpecialRoundStage == 2 then
		local survivors = {}
		for k,v in pairs(players) do
			if v:Alive() then
				table.insert(survivors, v)
			end
		end
		if #survivors == 1 then
			self:EndTheRound(2, survivors[1])
			return
		elseif #survivors == 0 then
			self:EndTheRound(3, nil)
			return
		end
		
		// round time ended
		if self.RoundStartTime + self.CurrentRoundTimeMax < CurTime() then
			self:EndTheRound(3, nil)
			return
		end
	end

	// keep playing.
end


function GM:DoRoundDeaths(dead, attacker)
	if self.RoundStage == self.Round.Playing then
		self.RoundLastDeath = CurTime() + 2
	end
end

// 1 Murderer wins
// 2 Murderer loses
// 3 Murderer rage quit
function GM:EndTheRound(reason, murderer)
	if self.RoundStage != self.Round.Playing then return end

	local players = team.GetPlayers(2)
	
	for k, ply in pairs(players) do
		if ply:GetMaterial() == "models/wireframe" then
			ply:SetMaterial("")
		end
	end
	self.SpawnProtectionActive = false
	
	for k, ply in pairs(players) do
		ply:SetMurdererRevealed(false)
		ply:UnMurdererDisguise()
	end

	if reason == 3 then
		if murderer then
			local col = murderer:GetPlayerColor()
			local msgs = Translator:AdvVarTranslate(translate.murdererDisconnectKnown, {
				murderer = {text = murderer:Nick() .. ", " .. murderer:GetBystanderName(), color = Color(col.x * 255, col.y * 255, col.z * 255)}
			})
			local ct = ChatText(msgs)
			ct:SendAll()
			-- ct:Add(", it was ")
			-- ct:Add(murderer:Nick() .. ", " .. murderer:GetBystanderName(), Color(col.x * 255, col.y * 255, col.z * 255))
		else
			local ct = ChatText()
			ct:Add(translate.murdererDisconnect)
			ct:SendAll()
		end
	elseif reason == 2 then
		local col = murderer:GetPlayerColor()
		local msgs = Translator:AdvVarTranslate(translate.winBystandersMurdererWas, {
			murderer = {text = murderer:Nick() .. ", " .. murderer:GetBystanderName(), color = Color(col.x * 255, col.y * 255, col.z * 255)}
		})
		local ct = ChatText()
		ct:Add(translate.winBystanders, Color(20, 120, 255))
		ct:AddParts(msgs)
		ct:SendAll()
	elseif reason == 1 then
		local col = murderer:GetPlayerColor()
		local msgs = Translator:AdvVarTranslate(translate.winMurdererMurdererWas, {
			murderer = {text = murderer:Nick() .. ", " .. murderer:GetBystanderName(), color = Color(col.x * 255, col.y * 255, col.z * 255)}
		})
		local ct = ChatText()
		ct:Add(translate.winMurderer, Color(190, 20, 20))
		ct:AddParts(msgs)
		ct:SendAll()
	end

	net.Start("DeclareWinner")
	net.WriteUInt(reason, 8)
	if murderer then
		net.WriteEntity(murderer)
		net.WriteVector(murderer:GetPlayerColor())
		net.WriteString(murderer:GetBystanderName())
	else
		net.WriteEntity(Entity(0))
		net.WriteVector(Vector(1, 1, 1))
		net.WriteString("?")
	end

	for k, ply in pairs(team.GetPlayers(2)) do
		net.WriteUInt(1, 8)
		net.WriteEntity(ply)
		net.WriteUInt(ply.LootCollected, 32)
		net.WriteVector(ply:GetPlayerColor())
		net.WriteString(ply:GetBystanderName())
	end
	net.WriteUInt(0, 8)

	net.Broadcast()

	for k, ply in pairs(players) do
		if !ply.HasMoved && !ply.Frozen && self.AFKMoveToSpec:GetBool() then
			local oldTeam = ply:Team()
			ply:SetTeam(1)
			GAMEMODE:PlayerOnChangeTeam(ply, 1, oldTeam)

			local col = ply:GetPlayerColor()
			local msgs = Translator:AdvVarTranslate(translate.teamMovedAFK, {
				player = {text = ply:Nick(), color = Color(col.x * 255, col.y * 255, col.z * 255)},
				team = {text = team.GetName(1), color = team.GetColor(2)}
			})
			local ct = ChatText()
			ct:AddParts(msgs)
			ct:SendAll()
		end
		if ply:Alive() then
			ply:Freeze(false)
			ply.Frozen = false
		end
	end
	self.RoundUnFreezePlayers = nil

	self.MurdererLastKill = nil

	hook.Call("OnEndRound")
	hook.Run("OnEndRoundResult", reason)
	self.RoundCount = self.RoundCount + 1
	local limit = self.RoundLimit:GetInt()
	if limit > 0 then
		if self.RoundCount >= limit then
			self:ChangeMap()
			self.SpecialRoundStage = 0
			self:SetRound(4)
			return
		end
	end
	self.SpecialRoundStage = 0
	self:SetRound(2)
end

function GM:StartNewRound()
	local players = team.GetPlayers(2)
	if #players <= 1 then 
		local ct = ChatText()
		ct:Add(translate.minimumPlayers, Color(255, 150, 50))
		ct:SendAll()
		self:SetRound(self.Round.NotEnoughPlayers)
		return
	end

	local ct = ChatText()
	ct:Add(translate.roundStarted)
	ct:SendAll()

	self.RoundUnFreezePlayers = CurTime() + 10
	self.RoundStartTime = self.RoundUnFreezePlayers
	self.SpawnProtectionStartTime = self.RoundUnFreezePlayers
	self.CurrentRoundTimeMax = math.max(self.RoundTimeMax:GetInt(), 0)
	self.CurrentSpawnProtection = math.max(self.SpawnProtection:GetInt(), 0)
	self.SpawnProtectionActive = true
	if self.SpecialRoundCountdown == 0 then
		if self.SpecialRoundForce == 0 then
			self.SpecialRoundStage = math.random(1, 2)
		else
			self.SpecialRoundStage = self.SpecialRoundForce
			self.SpecialRoundForce = 0
		end
		self.SpecialRoundCountdown = math.max(self.SpecialRoundCountdownStart:GetInt(), 0)
	else
		self.SpecialRoundCountdown = self.SpecialRoundCountdown - 1
	end

	local players = team.GetPlayers(2)
	for k,ply in pairs(players) do
		ply:UnSpectate()
	end
	game.CleanUpMap()
	self:InitPostEntityAndMapCleanup()



	local oldMurderer
	for k,v in pairs(players) do
		if v:GetMurderer() then
			oldMurderer = v
		end
	end
	
	if self.SpecialRoundStage == 0 then
		local murderer

		// get the weight multiplier
		local weightMul = self.MurdererWeight:GetFloat()

		// pick a random murderer, weighted
		local rand = WeightedRandom()
		for k, ply in pairs(players) do
			if self.ForceNextGunner == nil || !IsValid(self.ForceNextGunner) || self.ForceNextGunner != ply then
				rand:Add(ply.MurdererChance ^ weightMul, ply)
			end
			ply.MurdererChance = ply.MurdererChance + 1
		end
		murderer = rand:Roll()

		// allow admins to specify next murderer
		if self.ForceNextMurderer && IsValid(self.ForceNextMurderer) && self.ForceNextMurderer:Team() == 2 then
			murderer = self.ForceNextMurderer
			self.ForceNextMurderer = nil
		end

		if IsValid(murderer) then
			murderer:SetMurderer(true)
		end
		for k, ply in pairs(players) do
			if ply != murderer then
				ply:SetMurderer(false)
			end
			ply:StripWeapons()
			ply:KillSilent()
			ply:Spawn()
			ply:Freeze(true)
			local vec = Vector(0, 0, 0)
			vec.x = math.Rand(0, 1)
			vec.y = math.Rand(0, 1)
			vec.z = math.Rand(0, 1)
			ply:SetPlayerColor(vec)

			ply.LootCollected = 0
			ply.HasMoved = false
			ply.Frozen = true
			ply:CalculateSpeed()
			ply:GenerateBystanderName()
		end
		local noobs = table.Copy(players)
		table.RemoveByValue(noobs, murderer)
		local magnum = table.Random(noobs)
		if self.ForceNextGunner && IsValid(self.ForceNextGunner) && self.ForceNextGunner:Team() == 2 then
			magnum = self.ForceNextGunner
			self.ForceNextGunner = nil
		end
		if IsValid(magnum) then
			magnum:Give("weapon_mu_magnum")
		end
	elseif self.SpecialRoundStage == 1 then
		for k, ply in pairs(players) do
			local MurdererChanceSave = ply.MurdererChance
			ply:SetMurderer(true)
			ply.MurdererChance = MurdererChanceSave
			ply:StripWeapons()
			ply:KillSilent()
			ply:Spawn()
			ply:Freeze(true)
			local vec = Vector(0, 0, 0)
			vec.x = math.Rand(0, 1)
			vec.y = math.Rand(0, 1)
			vec.z = math.Rand(0, 1)
			ply:SetPlayerColor(vec)

			ply.LootCollected = 0
			ply.HasMoved = false
			ply.Frozen = true
			ply:CalculateSpeed()
			ply:GenerateBystanderName()
		end
	elseif self.SpecialRoundStage == 2 then
		for k, ply in pairs(players) do
			ply:SetMurderer(false)
			ply:StripWeapons()
			ply:KillSilent()
			ply:Spawn()
			ply:Freeze(true)
			local vec = Vector(0, 0, 0)
			vec.x = math.Rand(0, 1)
			vec.y = math.Rand(0, 1)
			vec.z = math.Rand(0, 1)
			ply:SetPlayerColor(vec)

			ply.LootCollected = 0
			ply.HasMoved = false
			ply.Frozen = true
			ply:CalculateSpeed()
			ply:GenerateBystanderName()
			
			ply:Give("weapon_mu_magnum")
		end
	end

	self.MurdererLastKill = CurTime()
	
	for k, ply in pairs(players) do
		ply:SetMaterial("models/wireframe")
	end

	self:SetRound(self.Round.Playing)
	hook.Call("OnStartRound")
end

function GM:PlayerLeavePlay(ply)
	if ply:GetMaterial() == "models/wireframe" then
		ply:SetMaterial("")
	end

	if ply:HasWeapon("weapon_mu_magnum") then
		ply:DropWeapon(ply:GetWeapon("weapon_mu_magnum"))
	end

	if self.RoundStage == 1 and self.SpecialRoundStage != 1 then
		if ply:GetMurderer() then
			self:EndTheRound(3, ply)
		end
	end
end

concommand.Add("mu_forcenextmurderer", function (ply, com, args)
	if !ply:IsAdmin() then return end
	if #args < 1 then return end

	local ent = Entity(tonumber(args[1]) or -1)
	if !IsValid(ent) || !ent:IsPlayer() then 
		ply:ChatPrint("not a player")
		return 
	end

	GAMEMODE.ForceNextMurderer = ent
	if GAMEMODE.ForceNextGunner == ent then
		GAMEMODE.ForceNextGunner = nil
	end
	local msgs = Translator:AdvVarTranslate(translate.adminMurdererSelect, {
		player = {text = ent:Nick(), color = team.GetColor(2)}
	})
	local ct = ChatText()
	ct:AddParts(msgs)
	ct:Send(ply)
end)

concommand.Add("mu_forcenextgunner", function (ply, com, args)
	if !ply:IsAdmin() then return end
	if #args < 1 then return end

	local ent = Entity(tonumber(args[1]) or -1)
	if !IsValid(ent) || !ent:IsPlayer() then 
		ply:ChatPrint("not a player")
		return 
	end

	GAMEMODE.ForceNextGunner = ent
	if GAMEMODE.ForceNextMurderer == ent then
		GAMEMODE.ForceNextMurderer = nil
	end
	local msgs = Translator:AdvVarTranslate(translate.adminGunnerSelect, {
		player = {text = ent:Nick(), color = team.GetColor(2)}
	})
	local ct = ChatText()
	ct:AddParts(msgs)
	ct:Send(ply)
end)

concommand.Add("mu_round_time", function (ply, com, args)
	if IsValid(ply) && !ply:IsAdmin() then return end
	if #args < 1 then return end
	
	local argInt = tonumber(args[1])
	if argInt == nil then return end
	
	if GAMEMODE.RoundStage != 1 then return end
	
	GAMEMODE.RoundStartTime = CurTime()
	GAMEMODE.CurrentRoundTimeMax = math.max(argInt, 0)
	
	GAMEMODE:NetworkRound()
end)

concommand.Add("mu_special_round_countdown", function (ply, com, args)
	if IsValid(ply) && !ply:IsAdmin() then return end
	if #args < 1 then return end
	
	local argInt = tonumber(args[1])
	if argInt == nil then return end
	
	GAMEMODE.SpecialRoundCountdown = math.max(argInt, 0)
	
	GAMEMODE:NetworkRound()
end)

concommand.Add("mu_special_round_force", function (ply, com, args)
	if IsValid(ply) && !ply:IsAdmin() then return end
	if #args < 1 then return end
	
	local argInt = tonumber(args[1])
	if argInt == nil then return end
	if argInt < 1 || argInt > 2 then return end
	
	GAMEMODE.SpecialRoundForce = argInt
	
	local text = Translator:VarTranslate(translate.specialRoundForce, {
		name = translate["specialRoundName" .. tostring(GAMEMODE.SpecialRoundForce)]
	})
	if IsValid(ply) then
		ply:ChatPrint(text)
	else
		print(text)
	end
end)

function GM:ChangeMap()
	if #self.MapList > 0 then
		if MapVote then
			// only match maps that we have specified
			local prefix = {}
			for k, map in pairs(self.MapList) do
				table.insert(prefix, map .. "%.bsp$")
			end
			MapVote.Start(nil, nil, nil, prefix)
			return
		end
		self:RotateMap()
	end
end

function GM:RotateMap()
	local map = game.GetMap()
	local index 
	for k, map2 in pairs(self.MapList) do
		if map == map2 then
			index = k
		end
	end
	if !index then index = 1 end
	index = index + 1
	if index > #self.MapList then
		index = 1
	end
	local nextMap = self.MapList[index]
	print("[Murder] Rotate changing map to " .. nextMap)
	local ct = ChatText()
	ct:Add(Translator:QuickVar(translate.mapChange, "map", nextMap))
	ct:SendAll()
	hook.Call("OnChangeMap", GAMEMODE)
	timer.Simple(5, function ()
		RunConsoleCommand("changelevel", nextMap)
	end)
end

GM.MapList = {}

local defaultMapList = {
	"clue",
	"cs_italy",
	"ttt_clue",
	"cs_office",
	"de_chateau",
	"de_tides",
	"de_prodigy",
	"mu_nightmare_church",
	"dm_lockdown",
	"housewithgardenv2",
	"de_forest"
}

function GM:SaveMapList()

	// ensure the folders are there
	if !file.Exists("murder/","DATA") then
		file.CreateDir("murder")
	end

	local txt = ""
	for k, map in pairs(self.MapList) do
		txt = txt .. map .. "\r\n"
	end
	file.Write("murder/maplist.txt", txt)
end

function GM:LoadMapList() 
	local jason = file.ReadDataAndContent("murder/maplist.txt")
	if jason then
		local tbl = {}
		local i = 1
		for map in jason:gmatch("[^\r\n]+") do
			table.insert(tbl, map)
		end
		self.MapList = tbl
	else
		local tbl = {}
		for k, map in pairs(defaultMapList) do
			if file.Exists("maps/" .. map .. ".bsp", "GAME") then
				table.insert(tbl, map)
			end
		end
		self.MapList = tbl
		self:SaveMapList()
	end
end
