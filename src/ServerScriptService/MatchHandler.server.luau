--[[
=============================================================
  MAP MATCH HANDLER (Server) — TAHAP 1
  
  Terima player yang datang dari Lobby.
  Untuk Tahap 1: cuma spawn player & log.
  Nanti di tahap lanjut: mulai match, countdown, dll.
  
  PLACE INI DI: ServerScriptService (di MAP place)
  NAMA SCRIPT: MatchHandler
=============================================================
]]

local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ============================================================
--  KONFIGURASI — GANTI DENGAN PLACE ID LOBBY KAMU!
-- ============================================================
local LOBBY_PLACE_ID = 72436553849314  -- Place ID PUBG LOBBY (benar)

-- ============================================================
--  TERIMA PLAYER DARI LOBBY
-- ============================================================
Players.PlayerAdded:Connect(function(player)
	print(string.format("[MAP] %s masuk ke Map PUBG", player.Name))

	-- Cek apakah datang dari teleport (ada TeleportData)
	local joinData = player:GetJoinData()
	local teleportData = joinData.TeleportData

	if teleportData then
		print(string.format("[MAP] %s datang dengan mode: %s", 
			player.Name, tostring(teleportData.mode)))
		-- Bisa simpan mode (solo/duo/squad) untuk logika match nanti
		player:SetAttribute("GameMode", teleportData.mode or "solo")
	else
		print(string.format("[MAP] %s join langsung (bukan dari lobby)", player.Name))
		player:SetAttribute("GameMode", "solo")
	end
end)

-- ============================================================
--  FUNGSI: Kembalikan player ke Lobby (dipakai saat match selesai)
-- ============================================================
local function returnToLobby(player)
	if LOBBY_PLACE_ID == 0 then
		warn("[MAP] LOBBY_PLACE_ID belum diset!")
		return
	end

	local success, err = pcall(function()
		TeleportService:Teleport(LOBBY_PLACE_ID, player)
	end)

	if not success then
		warn("[MAP] Gagal kembali ke lobby: " .. tostring(err))
	end
end

-- Expose untuk script lain (misal saat match selesai)
local returnFunc = ReplicatedStorage:FindFirstChild("ReturnToLobby")
if not returnFunc then
	returnFunc = Instance.new("BindableFunction")
	returnFunc.Name = "ReturnToLobby"
	returnFunc.Parent = ReplicatedStorage
end
returnFunc.OnInvoke = returnToLobby

-- ============================================================
--  CONTOH: Tombol/perintah untuk kembali ke lobby
--  (untuk test — nanti diganti dengan logika "match selesai")
-- ============================================================
-- Misal player ketik "/lobby" di chat untuk balik (testing)
Players.PlayerAdded:Connect(function(player)
	player.Chatted:Connect(function(message)
		if message:lower() == "/lobby" then
			returnToLobby(player)
		end
	end)
end)

print("===========================================")
print("[MAP MATCH HANDLER] Siap (Tahap 1)")
print("  Lobby Place ID: " .. LOBBY_PLACE_ID)
print("  Ketik /lobby di chat untuk test kembali ke lobby")
print("===========================================")