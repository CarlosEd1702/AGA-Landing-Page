--[[
================================================================================
 QRRedeemController — Reclamo manual de QR (tecla R) + UI de resultado (AGA)
================================================================================
 companyId = "aga" · vale para los 4 placeIds de AGA (cada lobby registra su
 AGAQRRedeemService server-side con su Experience; este cliente es genérico).

 Funciones:
  - Tecla R: abre/cierra el panel QRRedeemGui (TextBox + CANJEAR).
  - ClaimButton: invoca ClaimQRRemote → resultado a PromoRewardGui.
  - PromoRewardGui: RewardFrame (líneas de recompensa, solo monedas por ahora)
    y ErrorFrame (mensaje explicativo: ya reclamado / código no existe / otra exp).

 ESTRUCTURA ESPERADA (crear en StarterGui):
   QRRedeemGui (ScreenGui, ResetOnSpawn=false)
     Panel: TitleLabel · CodeBox (TextBox) · ClaimButton · FeedbackLabel · CloseButton
   PromoRewardGui (ScreenGui, ResetOnSpawn=false)
     RewardFrame: TitleLabel · RewardLinesLabel · ContinueButton
     ErrorFrame:  ErrorLabel · CloseButton
   HintGui (ScreenGui, ResetOnSpawn=false): HintLabel "Presiona R para canjear QR"
================================================================================
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local redeemGui = playerGui:WaitForChild("QRRedeemGui", 15)
local rewardGui = playerGui:WaitForChild("PromoRewardGui", 15)
local hintGui = playerGui:FindFirstChild("HintGui")

local panel = redeemGui and redeemGui:FindFirstChild("Panel")
local rewardFrame = rewardGui and rewardGui:FindFirstChild("RewardFrame")
local errorFrame = rewardGui and rewardGui:FindFirstChild("ErrorFrame")

local codeBox = panel and panel:FindFirstChild("CodeBox")
local claimButton = panel and panel:FindFirstChild("ClaimButton")
local feedback = panel and panel:FindFirstChild("FeedbackLabel")
local panelClose = panel and panel:FindFirstChild("CloseButton")
local titleLabel = rewardFrame and rewardFrame:FindFirstChild("TitleLabel")
local rewardLines = rewardFrame and rewardFrame:FindFirstChild("RewardLinesLabel")
local continueBtn = rewardFrame and rewardFrame:FindFirstChild("ContinueButton")
local errorLabel = errorFrame and errorFrame:FindFirstChild("ErrorLabel")
local errorClose = errorFrame and errorFrame:FindFirstChild("CloseButton")

local redeemOpen = false
local savedGuis = {}

local function root()
	return ReplicatedStorage:FindFirstChild("AGA_Racing") or ReplicatedStorage
end

local function findRemote(name)
	local folder = root():FindFirstChild("QRRemotes")
	return folder and folder:FindFirstChild(name) or nil
end

local function hideOtherGuis()
	savedGuis = {}
	for _, g in ipairs(playerGui:GetChildren()) do
		if g:IsA("ScreenGui") and g ~= redeemGui and g ~= rewardGui and g ~= hintGui then
			savedGuis[g] = g.Enabled
			g.Enabled = false
		end
	end
end

local function restoreGuis()
	for g, state in pairs(savedGuis) do
		g.Enabled = state
	end
	savedGuis = {}
end

local function showReward(result)
	hideOtherGuis()
	rewardGui.Enabled = true
	if result and result.Success then
		errorFrame.Visible = false
		rewardFrame.Visible = true
		if titleLabel then titleLabel.Text = "🎉 ¡Recompensa reclamada!" end
		local lines = result.RewardLines or {}
		if #lines == 0 and (result.Coins or 0) > 0 then
			lines = { "💧 +" .. tostring(result.Coins) .. " Coins" }
		end
		if rewardLines then rewardLines.Text = table.concat(lines, "\n") end
	else
		rewardFrame.Visible = false
		errorFrame.Visible = true
		if errorLabel then
			errorLabel.Text = result and result.ErrorMessage or "No se pudo reclamar el código."
		end
	end
end

local function setPanelVisible(visible)
	redeemOpen = visible
	if redeemGui then redeemGui.Enabled = visible end
	if hintGui and hintGui:FindFirstChild("HintLabel") then
		hintGui:FindFirstChild("HintLabel").Visible = not visible
	end
end

local function doClaim(code)
	if not code or code == "" then
		if feedback then feedback.Text = "Ingresá el código del QR." end
		return
	end
	if feedback then feedback.Text = "Reclamando…" end
	local remote = findRemote("ClaimQRRemote")
	if not remote then
		if feedback then feedback.Text = "Servicio de canje no disponible." end
		return
	end
	local ok, result = pcall(function()
		return remote:InvokeServer({ code = code })
	end)
	if not ok then
		if feedback then feedback.Text = "Error de conexión." end
		return
	end
	if typeof(result) == "table" and result.Success then
		if feedback then feedback.Text = "✅ +" .. tostring(result.Coins or 0) .. " Coins" end
		task.wait(0.4)
		setPanelVisible(false)
		showReward(result)
	else
		if feedback then feedback.Text = tostring(result and result.ErrorMessage or "Error") end
	end
end

-- Toggle con tecla R
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.R then
		if redeemOpen then
			setPanelVisible(false)
			restoreGuis()
		else
			setPanelVisible(true)
		end
	end
end)

if claimButton then
	claimButton.Activated:Connect(function()
		local code = codeBox and codeBox.Text or ""
		doClaim(code)
	end)
end
if codeBox then
	codeBox.FocusLost:Connect(function(enterPressed)
		if enterPressed then doClaim(codeBox.Text) end
	end)
end
if panelClose then
	panelClose.Activated:Connect(function()
		setPanelVisible(false)
		restoreGuis()
	end)
end
if continueBtn then
	continueBtn.Activated:Connect(function()
		rewardGui.Enabled = false
		restoreGuis()
	end)
end
if errorClose then
	errorClose.Activated:Connect(function()
		rewardGui.Enabled = false
		restoreGuis()
	end)
end

setPanelVisible(false)
print("[AGAQRRedeem] listo — presiona R para canjear QR")
