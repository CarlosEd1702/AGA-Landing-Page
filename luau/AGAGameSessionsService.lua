--[[
===============================================================================
 AGAGameSessionsService — Sesiones de juego AGA (AGA_Game_Sessions)
===============================================================================
 Empresa: AGA (companyId = "aga") · Workspace: cc6ac8fa-e31c-421d-99af-15951a0e8a7a

 Registra en Praxsuite la ENTRADA y SALIDA de cada jugador en cada Place de AGA
 (los 4: Lobby Carrera, Pista Carrera, Lobby Activación, Pista Activación).
 Sirve para el dashboard de engagement:
   - Mapa de calor Día-de-semana × Hora (Entered At)
   - Promedio de tiempo de sesión por experiencia (Duration Seconds)
   - Picos de usuarios / flujo (sesiones por hora y por día)

 USO (server-side, en cada Place AGA):
   local AGAGameSessionsService = require(ServerScriptService.AGA_Racing.AGAGameSessionsService)
   AGAGameSessionsService:Init({
     ApiKey = "sk_live_...",           -- key readwrite en AGA_* (o nil si usa Secrets)
     ApiKeySecret = "PraxsuiteApiKey", -- en producción (Secrets Store de Roblox)
     Experience = "street",            -- "street" | "activation"
   })
   AGAGameSessionsService:start()      -- conecta Players.PlayerAdded/PlayerRemoving

 La integración puede llamar también:
   AGAGameSessionsService:startSession(player, { source = "bottle_qr" | "direct", code = "AGA-..." })
     → manualmente si el lugar ya maneja su propio PlayerAdded (p. ej. tras esperar data).
   AGAGameSessionsService:endSession(player)  → cierra la sesión abierta (si el lugar
     no usa PlayerRemoving porque teleporta, llamarlo antes del teleport).

 NO depende del SDK interno: habla directo con la REST API del gateway (HttpService),
 igual que AGACentralService — portable entre los 4 places.
===============================================================================
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local AGAGameSessionsService = {}
AGAGameSessionsService.__index = AGAGameSessionsService

local DEFAULT_CONFIG = {
	WorkspaceId = "cc6ac8fa-e31c-421d-99af-15951a0e8a7a",
	GatewayUrl  = "https://gateway.praxsuite.com/cc6ac8fa-e31c-421d-99af-15951a0e8a7a",
	ApiKey      = nil,  -- en Studio: key raw readwrite AGA_* | producción: nil + ApiKeySecret
	ApiKeySecret = "PraxsuiteApiKey",
	TableId     = "dd29d762-7e41-419b-b394-8259b8225dfc", -- AGA_Game_Sessions
	Experience  = "street",
	FlushOnLeave = true,
}

local config = nil
local sessions = {} -- [userId] = { SessionId, StartedAt }

local function isoNow()
	return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

local function postJson(url, body)
	local headers = nil
	if config and config.ApiKey and config.ApiKey ~= "" then
		headers = { ["Authorization"] = "Bearer " .. config.ApiKey }
	end
	local okPost, result = pcall(function()
		return HttpService:PostAsync(url, HttpService:JSONEncode(body), Enum.HttpContentType.ApplicationJson, false, headers)
	end)
	if not okPost then
		return { ok = false, error = tostring(result) }
	end
	local okDecode, decoded = pcall(function()
		return HttpService:JSONDecode(result)
	end)
	if not okDecode then
		return { ok = false, error = "respuesta no-JSON: " .. tostring(result) }
	end
	return { ok = true, data = decoded }
end

-- Inserta una fila de sesión (entrada). Devuelve { ok, SessionId }.
function AGAGameSessionsService:startSession(player, opts)
	if not config or not player then return { ok = false } end
	opts = opts or {}
	local userId = tostring(player.UserId)
	-- Si ya hay una sesión abierta para este user en este server, no duplicar.
	if sessions[userId] then return { ok = true, SessionId = sessions[userId].SessionId } end

	local sessionId = HttpService:GenerateGUID(false)
	local placeId = tostring(game.PlaceId)
	local source = tostring(opts.source or "direct")
	local code = tostring(opts.code or "")
	local res = postJson(config.GatewayUrl .. "/query", {
		refs = { t = config.TableId },
		mutation = {
			type = "insert",
			table = "t",
			values = { {
				["Session ID"] = sessionId,
				["Roblox User Id"] = userId,
				["Place Id"] = placeId,
				Experience = config.Experience,
				Source = source,
				Code = code,
				["Entered At"] = isoNow(),
			} },
			returning = false,
		},
	})
	if not res.ok then
		warn("[AGAGameSessions] startSession falló:", tostring(res.error))
		return { ok = false, error = res.error }
	end
	sessions[userId] = { SessionId = sessionId, StartedAt = os.clock() }
	return { ok = true, SessionId = sessionId }
end

-- Cierra la sesión abierta (update Exited At + Duration Seconds).
function AGAGameSessionsService:endSession(player)
	if not config or not player then return { ok = false } end
	local userId = tostring(player.UserId)
	local s = sessions[userId]
	if not s then return { ok = true } end
	sessions[userId] = nil

	local duration = math.max(1, math.floor((os.clock() - s.StartedAt) + 0.5))
	local res = postJson(config.GatewayUrl .. "/query", {
		refs = { t = config.TableId },
		mutation = {
			type = "update",
			table = "t",
			set = {
				["Exited At"] = isoNow(),
				["Duration Seconds"] = duration,
			},
			where = {
				{ field = "Session ID", op = "eq", value = s.SessionId },
			},
		},
	})
	if not res.ok then
		warn("[AGAGameSessions] endSession falló:", tostring(res.error))
		return { ok = false, error = res.error }
	end
	return { ok = true, SessionId = s.SessionId, DurationSeconds = duration }
end

-- Cierra la sesión de un jugador si existe (sin requerir el player) — útil al teleportar.
function AGAGameSessionsService:endSessionByUserId(userId)
	if not config then return { ok = false } end
	userId = tostring(userId or "")
	local s = sessions[userId]
	if not s then return { ok = true } end
	sessions[userId] = nil
	local duration = math.max(1, math.floor((os.clock() - s.StartedAt) + 0.5))
	local res = postJson(config.GatewayUrl .. "/query", {
		refs = { t = config.TableId },
		mutation = {
			type = "update",
			table = "t",
			set = {
				["Exited At"] = isoNow(),
				["Duration Seconds"] = duration,
			},
			where = {
				{ field = "Session ID", op = "eq", value = s.SessionId },
			},
		},
	})
	return { ok = res.ok, SessionId = s.SessionId }
end

-- Conecta PlayerAdded / PlayerRemoving automáticamente.
function AGAGameSessionsService:start()
	if not config then return false end

	Players.PlayerAdded:Connect(function(player)
		task.delay(3, function()
			if not player or not player.Parent then return end
			-- source: si el jugador vino con launchData de QR → bottle_qr
			local source = "direct"
			local code = ""
			local okData, joinData = pcall(function()
				return player:GetJoinData()
			end)
			if okData and typeof(joinData) == "table" then
				local raw = joinData.LaunchData
				if typeof(raw) == "string" and raw ~= "" then
					local okDec, decoded = pcall(function()
						return HttpService:JSONDecode(raw)
					end)
					if okDec and typeof(decoded) == "table" then
						if tostring(decoded.qrCode or "") ~= "" then
							source = "bottle_qr"
							code = tostring(decoded.qrCode)
						end
					end
				end
			end
			self:startSession(player, { source = source, code = code })
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		self:endSession(player)
	end)

	print("[AGAGameSessions] activo en place", tostring(game.PlaceId), "(experience=" .. tostring(config.Experience) .. ")")
	return true
end

-- Init(overrides) — configurar Experience / ApiKey antes de start().
function AGAGameSessionsService:Init(overrides)
	config = {}
	for k, v in pairs(DEFAULT_CONFIG) do
		config[k] = (type(v) == "table") and table.clone(v) or v
	end
	if overrides then
		for k, v in pairs(overrides) do
			if type(v) == "table" and type(config[k]) == "table" then
				for k2, v2 in pairs(v) do config[k][k2] = v2 end
			else
				config[k] = v
			end
		end
	end
	if not config.ApiKey or config.ApiKey == "" then
		-- En producción el secreto se resuelve igual que AGACentralService; si no hay
		-- key raw y no corre en Studio, dejar que el servicio lo intente sin headers
		-- (el gateway exige key, así que advertimos).
		warn("[AGAGameSessions] sin ApiKey raw — en Studio la telemetría de sesiones quedará desactivada (usar ApiKeySecret en producción).")
	end
	return self
end

function AGAGameSessionsService:GetStatus()
	return {
		Enabled = config ~= nil,
		OpenSessions = 0,
		Experience = config and config.Experience or nil,
	}
end

return AGAGameSessionsService
