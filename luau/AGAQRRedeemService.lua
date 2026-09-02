--[[
================================================================================
 AGAQRRedeemService — Flujo server-side de reclamo QR (1 copia por juego AGA)
================================================================================
 companyId = "aga" · experiencia: "street" | "activation"

 FLUJO (server-authoritative):
   1) Cliente invoca el RemoteFunction ClaimQRRemote con { code }.
   2) Aquí se valida contra QRPromosConfig (recompensa local del lote).
   3) Se llama a AGACentralService:ClaimCode → consume el código en el backend
      CENTRAL (AGA_Promotions): si ya fue reclamado en el OTRO juego, responde
      { Success=false, ErrorMessage="Este código ya ha sido reclamado..." }.
   4) Si Success: se acreditan las Coins en el perfil LOCAL del lobby
      (PlayerDataService.addCoins) — el dinero con el que juega en ESTA sesión.
   5) El inventario/registro CENTRAL (coins, desbloqueos) lo actualiza
      AGACentralService sobre AGA_Inventories, compartido entre juegos.

 La integración de cada juego aporta su PlayerDataService local (API de coins)
 y su Experience key. Nada de esto toca LocalScripts: es 100% server-side.

 USO (Bootstrap del lobby):
   local AGAQRRedeemService = require(script.Parent:WaitForChild("AGAQRRedeemService"))
   AGAQRRedeemService:Init({
     Experience = "street",  -- o "activation"
     PlayerDataService = PlayerDataService,   -- lobby local (addCoins)
     Central = AGACentralService,             -- AGACentralService:Init() ya hecho
   })
================================================================================
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local AGAQRRedeemService = {}
AGAQRRedeemService.__index = AGAQRRedeemService

local initialized = false
local config = nil

local function ensureRemote(parent, name, className)
	local child = parent:FindFirstChild(name)
	if child and not child:IsA(className) then
		child:Destroy()
		child = nil
	end
	if not child then
		child = Instance.new(className)
		child.Name = name
		child.Parent = parent
	end
	return child
end

-- Crea o reutiliza el namespace de remotes del QR dentro de AGA_Racing
local function getRemoteFolder()
	local root = ReplicatedStorage:FindFirstChild("AGA_Racing") or ReplicatedStorage
	local folder = root:FindFirstChild("QRRemotes")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "QRRemotes"
		folder.Parent = root
	end
	return folder
end

function AGAQRRedeemService:Init(opts)
	if initialized then return true end
	if type(opts) ~= "table" or not opts.PlayerDataService or not opts.Central then
		error("[AGAQRRedeem] Init requiere { Experience, PlayerDataService, Central }")
	end
	config = {
		Experience = tostring(opts.Experience or "street"),
		PlayerDataService = opts.PlayerDataService,
		Central = opts.Central,
		QRPromosConfig = opts.QRPromosConfig, -- opcional: si el lobby ya lo require
	}
	if not config.QRPromosConfig then
		local sharedRoot = ReplicatedStorage:FindFirstChild("AGA_Racing") or ReplicatedStorage
		local mods = sharedRoot:FindFirstChild("Modules") or sharedRoot
		config.QRPromosConfig = require(mods:WaitForChild("QRPromosConfig"))
	end

	local folder = getRemoteFolder()
	local claimRemote = ensureRemote(folder, "ClaimQRRemote", "RemoteFunction")

	claimRemote.OnServerInvoke = function(player, request)
		if typeof(player) ~= "userdata" or not player:IsA("Player") then
			return { Success = false, ErrorMessage = "Solicitud inválida." }
		end
		return AGAQRRedeemService:claimForPlayer(player, request)
	end

	initialized = true
	print("[AGAQRRedeem] listo (" .. config.Experience .. ")")
	return true
end

-- ============================================================================
-- CLAIM (server-side)
-- ============================================================================
function AGAQRRedeemService:claimForPlayer(player, request)
	if not config then
		return { Success = false, ErrorMessage = "Servicio no inicializado." }
	end
	if typeof(request) ~= "table" then
		return { Success = false, ErrorMessage = "Solicitud inválida." }
	end
	local code = tostring(request.code or ""):upper():gsub("%s+", "")
	if code == "" then
		return { Success = false, ErrorMessage = "El código ingresado no existe." }
	end

	-- 1) Recompensa local definida para este código (QRPromosConfig)
	local reward = config.QRPromosConfig and config.QRPromosConfig.GetReward(code)
	if not reward then
		return { Success = false, ErrorMessage = "El código ingresado no existe." }
	end
	-- El código pertenece a la otra experiencia → rechazarlo aquí (el backend
	-- central igual lo rechazaría, pero el mensaje es más claro).
	if reward.Exp ~= config.Experience then
		return {
			Success = false,
			ErrorMessage = "Este código es para la experiencia '" ..
				(reward.Exp == "street" and "Carrera para Impresionar" or "Activación AGA") ..
				"'. Abrí la experiencia correcta para canjearlo.",
		}
	end

	-- 2) Consumo CENTRAL (anti duplicado entre ambos juegos + inventario global)
	local central = config.Central
	local claimRes = central:ClaimCode({
		code = code,
		userId = tostring(player.UserId),
		username = player.Name,
		experience = config.Experience,
		placeId = tostring(game.PlaceId),
	})
	if not claimRes.Success then
		return { Success = false, ErrorMessage = claimRes.ErrorMessage or "No se pudo canjear el código." }
	end

	-- 3) Acreditar monedas en el perfil LOCAL del lobby (con el que juega ahora)
	local coins = reward.Coins or 0
	local addOk = false
	if coins > 0 then
		local ok, result = pcall(function()
			return config.PlayerDataService.addCoins(player, coins)
		end)
		addOk = ok and result ~= nil
	end

	-- 4) Registrar crédito en el inventario CENTRAL (AGA_Inventories, global)
	local centralOk = false
	if coins > 0 then
		local okAdd = pcall(function()
			return central:AddCoins(tostring(player.UserId), coins)
		end)
		centralOk = okAdd
	end

	return {
		Success = true,
		Code = code,
		Coins = coins,
		Experience = config.Experience,
		RewardLines = {
			"💧 +" .. coins .. " Coins",
		},
		LocalApplied = addOk,
		CentralApplied = centralOk,
	}
end

return AGAQRRedeemService
