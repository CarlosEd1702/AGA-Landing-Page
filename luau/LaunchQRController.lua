--[[
================================================================================
 LaunchQRController — Lectura de launchData al iniciar sesión (AGA)
================================================================================
 Se ejecuta en CUALQUIERA de los 4 placeIds de AGA (Lobby/Pista de Carrera y de
 Activación). Al entrar, si el usuario vino desde la web del QR, `GetJoinData()`
 trae `LaunchData` = JSON { qrCode, companyId, experience }.

 Si companyId == "aga" y hay qrCode → abre el modal de reclamo (QRRedeemGui)
 con el código precargado. El reclamo real lo procesa el servidor (RemoteFunction
 ClaimQRRemote creado por AGAQRRedeemService); este controlador solo muestra la UI
 y dispara el claim; el resultado se pinta vía el BindableEvent PromoRewardBridge.

 ESTRUCTURA ESPERADA (crear en StarterGui):
   QRRedeemGui (ScreenGui, ResetOnSpawn=false)
     ├─ Panel (Frame) con TextBox "CodeBox", botón "ClaimButton", Label "FeedbackLabel", botón "CloseButton"
   PromoRewardGui (ScreenGui, ResetOnSpawn=false)
     ├─ RewardFrame (Frame) con TitleLabel, RewardLinesLabel, ContinueButton
     └─ ErrorFrame (Frame) con ErrorLabel, CloseButton

 NOTA: en Studio el LaunchData llega vacío; probar con la experiencia publicada.
================================================================================
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local QR_REDEEM_GUI_NAME = "QRRedeemGui"
local REWARD_GUI_NAME = "PromoRewardGui"

local function findSharedRemote(name)
	local root = ReplicatedStorage:FindFirstChild("AGA_Racing") or ReplicatedStorage
	local folder = root:FindFirstChild("QRRemotes")
	return folder and folder:FindFirstChild(name) or nil
end

local function getOrWaitGui(name)
	local gui = playerGui:FindFirstChild(name)
	if not gui then
		gui = playerGui:WaitForChild(name, 10)
	end
	return gui
end

local function parseLaunchData()
	local ok, joinData = pcall(function()
		return player:GetJoinData()
	end)
	if not ok or typeof(joinData) ~= "table" then return nil end
	local raw = joinData.LaunchData
	if typeof(raw) ~= "string" or raw == "" then return nil end
	local decodeOk, decoded = pcall(function()
		return HttpService:JSONDecode(raw)
	end)
	if not decodeOk or typeof(decoded) ~= "table" then return nil end
	return decoded
end

-- Invoca el claim y devuelve el resultado { Success, Coins, ErrorMessage, ... }
local function invokeClaim(code)
	local remote = findSharedRemote("ClaimQRRemote")
	if not remote then
		return { Success = false, ErrorMessage = "Servicio de canje no disponible." }
	end
	local ok, result = pcall(function()
		return remote:InvokeServer({ code = code })
	end)
	if not ok then
		return { Success = false, ErrorMessage = "Error de conexión con el servidor." }
	end
	if typeof(result) ~= "table" then
		return { Success = false, ErrorMessage = "Respuesta inválida del servidor." }
	end
	return result
end

-- Abre el modal de reclamo con el código precargado y ejecuta el claim.
local function openRedeemWithCode(code, claimNow)
	code = tostring(code or ""):upper():gsub("%s+", "")
	if code == "" then return end

	local gui = getOrWaitGui(QR_REDEEM_GUI_NAME)
	if not gui then
		warn("[LaunchQR] No se encontró " .. QR_REDEEM_GUI_NAME)
		return
	end
	local panel = gui:FindFirstChild("Panel")
	local codeBox = panel and panel:FindFirstChild("CodeBox")
	local feedback = panel and panel:FindFirstChild("FeedbackLabel")

	gui.Enabled = true
	if codeBox and codeBox:IsA("TextBox") then
		codeBox.Text = code
	end
	if feedback then
		feedback.Text = "🎟️ Código " .. code .. " detectado. Reclamando…"
	end

	-- Dispara el claim por el deep link (auto)
	if claimNow ~= false then
		local result = invokeClaim(code)

		-- FEATURE FLAG server-side: si AGA no tiene el Add-On QR contratado
		-- (Entrega), el servidor responde ModuleDisabled=true. No abrimos la
		-- pantalla de recompensa: mostramos un aviso interno discreto en el
		-- panel y la experiencia sigue normal.
		if result.ModuleDisabled then
			warn("[LaunchQR] canje QR deshabilitado por config de módulo (entrega AGA):", result.ErrorMessage or "")
			gui.Enabled = false
			if feedback then
				feedback.Text = "El canje por QR no está disponible en esta experiencia."
			end
			task.delay(2.5, function()
				if gui and gui.Parent then gui.Enabled = false end
			end)
			return
		end

		-- Publica el resultado para que la UI de recompensa/error lo muestre
		local root = ReplicatedStorage:FindFirstChild("AGA_Racing") or ReplicatedStorage
		local bridge = root:FindFirstChild("PromoRewardBridge")
		if bridge and bridge:IsA("BindableEvent") then
			bridge:Fire(result)
		else
			-- Sin bridge: feedback mínimo
			if feedback then
				if result.Success then
					feedback.Text = "✅ +" .. tostring(result.Coins or 0) .. " Coins"
				else
					feedback.Text = "❌ " .. tostring(result.ErrorMessage or "Error")
				end
			end
		end
	end
end

-- ============================================================================
-- Punto de entrada
-- ============================================================================
local launch = parseLaunchData()
if launch and typeof(launch) == "table" and tostring(launch.companyId or ""):lower() == "aga" and tostring(launch.qrCode or "") ~= "" then
	task.wait(1.5) -- espera a que la UI/DataService del juego esté lista
	openRedeemWithCode(launch.qrCode, true)
	print("[LaunchQR] deep link AGA detectado:", launch.qrCode, "exp=", tostring(launch.experience or ""))
else
	print("[LaunchQR] sin launchData AGA")
end

return {
	openRedeemWithCode = openRedeemWithCode,
}
