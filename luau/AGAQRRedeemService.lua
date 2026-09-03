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

-- ============================================================================
-- FEATURE FLAG "qrRedemption" (Add-On): si AGAModuleConfig existe en el juego
-- con qrRedemption.Enabled = false (Entrega a AGA), este servicio responde
-- ModuleDisabled SIN procesar el reclamo. Fuente web espejo: web/config.js.
-- ============================================================================
local ModuleConfig = nil
local function loadModuleConfig()
	if ModuleConfig ~= nil then return ModuleConfig end
	local okRequire = pcall(function()
		local sss = game:GetService("ServerScriptService")
		local candidate = sss:FindFirstChild("AGA_Racing") and sss.AGA_Racing:FindFirstChild("AGAModuleConfig")
			or sss:FindFirstChild("AGAModuleConfig")
			or (script.Parent and script.Parent:FindFirstChild("AGAModuleConfig"))
		if not candidate then error("AGAModuleConfig no encontrado") end
		ModuleConfig = require(candidate)
	end)
	if not okRequire then
		ModuleConfig = false -- sin config → habilitado (compatibilidad demo)
	end
	return ModuleConfig
end

local function moduleEnabled(moduleKey)
	local cfg = loadModuleConfig()
	if cfg == false then return true end
	if type(cfg) == "table" and type(cfg.IsModuleEnabled) == "function" then
		return cfg.IsModuleEnabled(moduleKey)
	end
	return true
end

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

	-- ── FEATURE FLAG: módulo "qrRedemption" (Add-On) ──────────────────────
	-- Entrega a AGA (flag false): se IGNORA el reclamo sin validar códigos ni
	-- llamar al backend central. Respuesta controlada para que la UI del juego
	-- muestre un mensaje interno y la sesión no se rompa.
	if not moduleEnabled("qrRedemption") then
		return {
			Success = false,
			ModuleDisabled = true,
			ErrorMessage = "El canje por QR no está disponible en esta experiencia.",
		}
	end

	if typeof(request) ~= "table" then
		return { Success = false, ErrorMessage = "Solicitud inválida." }
	end
	local code = tostring(request.code or ""):upper():gsub("%s+", "")
	if code == "" then
		return { Success = false, ErrorMessage = "El código ingresado no existe." }
	end
	local isCampaign = request.campaign == true

	-- 1) Validar el código contra el lote local (mensajes claros). NO consume nada.
	--    EXCEPTO campañas de botella (launchData plano tipo "AGA_BOTTLE_PROMO"):
	--    ahí no hay código de lote individual → la atribución se registra igual.
	local reward = config.QRPromosConfig and config.QRPromosConfig.GetReward(code)
	if not isCampaign and not reward then
		return { Success = false, ErrorMessage = "El código ingresado no existe." }
	end
	-- El código pertenece a la otra experiencia → rechazarlo aquí (el backend
	-- central igual lo rechazaría, pero el mensaje es más claro).
	if not isCampaign and reward and reward.Exp ~= config.Experience then
		return {
			Success = false,
			ErrorMessage = "Este código es para la experiencia '" ..
				(reward.Exp == "street" and "Carrera para Impresionar" or "Activación AGA") ..
				"'. Abrí la experiencia correcta para canjearlo.",
		}
	end

	-- ──────────────────────────────────────────────────────────────────────────
	-- 2) DEMO AGA — ATRIBUCIÓN (sin recompensa por ahora)
	--    El QR de la botella simula la compra: registramos en AGA_QR_Scans que
	--    este usuario entró vía QR (UserId + PlaceId + Entered At + source bottle_qr).
	--    La UI muestra el welcome; NO se otorgan monedas ni items todavía.
	-- ──────────────────────────────────────────────────────────────────────────
	local central = config.Central
	local attr = central:RecordQRAttribution({
		code = code,
		userId = tostring(player.UserId),
		experience = config.Experience,
		placeId = tostring(game.PlaceId),
		source = "bottle_qr",
	})
	if not attr.Success then
		return {
			Success = false,
			ModuleDisabled = attr.ModuleDisabled == true,
			ErrorMessage = attr.ErrorMessage or "No se pudo registrar tu entrada por QR.",
		}
	end

	-- 3) GRANT REWARD (PREPARADO — Add-On futuro)
	--    Cuando AGA decida activar recompensas por QR, descomentar el bloque y
	--    acreditar local (PlayerDataService.addCoins) + central (AddCoins/UnlockItem):
	--
	--    local coins = reward.Coins or 0
	--    if coins > 0 then
	--        config.PlayerDataService.addCoins(player, coins)          -- perfil LOCAL
	--        central:AddCoins(tostring(player.UserId), coins)          -- inventario CENTRAL
	--    end
	--    -- items futuros → central:UnlockItem(userId, "cars"/"pets", itemKey)
	--    return { Success = true, Code = code, Coins = coins, RewardLines = {...} }
	--
	-- Mientras tanto: solo welcome + atribución.

	return {
		Success = true,
		Welcome = true,
		Code = code,
		Message = "¡Bienvenido desde la promoción AGA!",
		RewardLines = { "¡Bienvenido desde la promoción AGA! 🎉" },
		Experience = config.Experience,
		Coins = 0,
	}
end

return AGAQRRedeemService
