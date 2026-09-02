--[[
================================================================================
 AGACentralService — Backend centralizado AGA (2 experiencias Roblox)
================================================================================
 Empresa: AGA (companyId = "aga")
 Experiencias:
   1) "Carrera para Impresionar"  (Street Track)   → PLACE_STREET
   2) "Activación AGA"            (eventos privados) → PLACE_ACTIVATION

 REQUERIMIENTO CLAVE
   El inventario de recompensas y el registro de códigos QR canjeados están
   CENTRALIZADOS: si un usuario reclama un QR en cualquiera de los 2 juegos,
   el código se consume globalmente y la recompensa se acredita en AMBAS
   experiencias (porque ambos leen/escriben las MISMAS tablas en Praxsuite).

 CÓMO SE USA (en cada juego, server-side, NUNCA en LocalScript):
   local AGACentral = require(ServerScriptService.AGACentralService)
   AGACentral:Init()   -- una vez, al arrancar (Bootstrap)

   -- 1) Antes de otorgar: verificar que el código no esté consumido y que
   --    el inventario tenga espacio (todo en el backend central).
   local res = AGACentral:ClaimCode({
     code = code, userId = tostring(player.UserId),
     username = player.Name, experience = "street" | "activation",
     placeId = tostring(game.PlaceId)
   })
   if res.Success then
     -- res.Reward trae la recompensa: acreditar en el inventario central
   else
     -- res.ErrorMessage: "codigo invalido" / "ya reclamado" / "inventario lleno"
   end

 Este módulo NO depende del SDK interno de Praxsuite: habla directo con la
 API REST del gateway vía HttpService (portable entre juegos). La clave se
 lee desde un Secret/Config que NO debe exponerse al cliente.
================================================================================
]]

local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local AGACentralService = {}
AGACentralService.__index = AGACentralService

-- ============================================================================
-- CONFIGURACIÓN (editar por despliegue / por juego)
-- ============================================================================
local DEFAULT_CONFIG = {
	WorkspaceId  = "cc6ac8fa-e31c-421d-99af-15951a0e8a7a",
	GatewayUrl   = "https://gateway.praxsuite.com/cc6ac8fa-e31c-421d-99af-15951a0e8a7a",
	-- Clave de INGEST del servidor (sk_live_...) — en Studio se pone aquí;
	-- en producción leer de un Secret de Roblox o del Config del servidor.
	-- NUNCA debe vivir en un LocalScript ni replicarse al cliente.
	ApiKey       = "sk_live_", -- TODO: rellenar con la key readwrite de AGA

	-- Tablas centralizadas AGA (UUIDs del workspace)
	Tables = {
		Promotions  = "44f07e3b-94a0-4837-b475-343c5e29ab94", -- AGA_Promotions (códigos QR)
		Inventories = "8105d853-ffe8-448d-815b-3960ddbc7edc", -- AGA_Inventories (jugador global)
		ScanEvents  = "74c74a66-6c8f-443b-9d8e-ce964435434b", -- AGA_ScanEvents (aperturas)
		Rewards     = "29b7f8fe-550c-40c4-975d-788645df339f", -- AGA_Rewards (catálogo)
	},

	-- Experiencias AGA: cada una con su Lobby (destino de deep link / reclamo QR)
	-- y su Pista (a donde teleporta el lobby).
	Places = {
		street = {
			PlaceId = "123585082660675", Name = "Carrera para Impresionar", Lobby = "123585082660675",
			Track = "93293966670401",
		},
		activation = {
			PlaceId = "99086248105983", Name = "Activación AGA", Lobby = "99086248105983",
			Track = "108987866733849",
		},
	},

	-- Límite compartido de inventario por categoría
	InventoryLimits = {
		pets = 50, -- unlocked_pets máx (JSON array)
		cars = 20, -- unlocked_cars máx
	},

	Company   = "aga",
	Timeout   = 8,  -- segundos por request HTTP
	MaxRetry  = 2,
}

-- ============================================================================
-- ESTADO INTERNO
-- ============================================================================
local config = nil
local serverSide = false

-- ============================================================================
-- HELPERS HTTP (REST contra el gateway de Praxsuite)
-- ============================================================================

local function postJson(url, body, headers)
	local okPost, result = pcall(function()
		-- PostAsync con HttpContentType.ApplicationJson ya añade Content-Type;
		-- NO incluir "Content-Type" en headers (Roblox lo rechaza).
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

-- Query genérica: { ok, rows=tabla, found=boolean }
-- Formato where de PraxQL: { field, op, value }
local function queryRows(tableId, where, limit)
	local url = config.GatewayUrl .. "/query"
	local body = {
		refs = { t = tableId },
		query = {
			from = "t",
			select = {},
			where = where or {},
			limit = limit or 20,
		},
	}
	local headers = {
		["Authorization"] = "Bearer " .. config.ApiKey,
	}
	local res = postJson(url, body, headers)
	if not res.ok then return res end
	-- REST devuelve { data: [fila] }: decoded = { data = {...} }, el array está en .data
	local d = res.data or {}
	local payload = d
	if type(d.data) == "table" then payload = d.data end
	local rows = (type(payload) == "table") and payload or {}
	return { ok = true, rows = rows, found = #rows > 0, data = d }
end

local function mutate(tableId, mutation)
	local url = config.GatewayUrl .. "/query"
	local body = {
		refs = { t = tableId },
		mutation = mutation,
	}
	local headers = {
		["Authorization"] = "Bearer " .. config.ApiKey,
	}
	local res = postJson(url, body, headers)
	if not res.ok then return res end
	return { ok = true, data = res.data }
end

-- ============================================================================
-- CONFIG / INIT
-- ============================================================================

-- Init(overrides?: tabla) — llamar una vez desde el Bootstrap del juego.
function AGACentralService:Init(overrides)
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
	serverSide = RunService:IsServer()
	if not serverSide then
		warn("[AGACentral] debe ejecutarse server-side")
	end
	return self
end

function AGACentralService:GetConfig()
	return config
end

-- ============================================================================
-- INVENTARIO GLOBAL (AGA_Inventories — fila única por usuario)
-- ============================================================================

local function parseJsonList(raw)
	if raw == nil then return {} end
	if type(raw) == "table" then return raw end
	local okDecode, decoded = pcall(function()
		return HttpService:JSONDecode(tostring(raw))
	end)
	if okDecode and type(decoded) == "table" then return decoded end
	-- fallback: texto separado por comas
	local out = {}
	for token in tostring(raw):gmatch("[^,]+") do
		table.insert(out, tostring(token):gsub("%s", ""))
	end
	return out
end

local function jsonList(t)
	return HttpService:JSONEncode(t or {})
end

-- Devuelve el inventario del usuario (crea la fila si no existe).
-- Respuesta: { ok=true, inventory={ RobloxUserId, Coins, Trophies, UnlockedPets={...}, UnlockedCars={...} } }
function AGACentralService:GetInventory(userId)
	userId = tostring(userId)
	local q = queryRows(config.Tables.Inventories, {
		{ field = "Roblox User Id", op = "eq", value = userId },
	}, 1)
	if not q.ok then return q end

	if q.found then
		local row = q.rows[1]
		return {
			ok = true,
			inventory = {
				RobloxUserId = row["Roblox User Id"],
				Coins = tonumber(row.Coins) or 0,
				Trophies = tonumber(row.Trophies) or 0,
				UnlockedPets = parseJsonList(row["Unlocked Pets"]),
				UnlockedCars = parseJsonList(row["Unlocked Cars"]),
			},
		}
	end

	-- No existe → crear con ceros (mutación insert)
	local ins = mutate(config.Tables.Inventories, {
		type = "insert",
		table = "t",
		values = { {
			["Roblox User Id"] = userId,
			Coins = 0,
			Trophies = 0,
			["Unlocked Pets"] = jsonList({}),
			["Unlocked Cars"] = jsonList({}),
		} },
		returning = false,
	})
	if not ins.ok then return ins end
	return {
		ok = true,
		inventory = {
			RobloxUserId = userId,
			Coins = 0, Trophies = 0,
			UnlockedPets = {}, UnlockedCars = {},
		},
	}
end

-- Guarda el inventario completo del usuario (update por userId).
function AGACentralService:SaveInventory(userId, inventory)
	userId = tostring(userId)
	return mutate(config.Tables.Inventories, {
		type = "update",
		table = "t",
		set = {
			Coins = tonumber(inventory.Coins) or 0,
			Trophies = tonumber(inventory.Trophies) or 0,
			["Unlocked Pets"] = jsonList(inventory.UnlockedPets or {}),
			["Unlocked Cars"] = jsonList(inventory.UnlockedCars or {}),
			["Last Seen"] = os.date("!%Y-%m-%dT%H:%M:%SZ"),
		},
		where = {
			{ field = "Roblox User Id", op = "eq", value = userId },
		},
	})
end

-- ============================================================================
-- VERIFICACIÓN DE LÍMITE DE INVENTARIO (compartida entre juegos)
-- category: "pets" | "cars"
-- Respuesta: { ok=true, allowed=boolean, current=number, limit=number }
function AGACentralService:CheckInventoryLimit(userId, category)
	userId = tostring(userId)
	local limit = (config.InventoryLimits or {})[category] or 50
	local inv = self:GetInventory(userId)
	if not inv.ok then return inv end
	local current = 0
	if category == "pets" then
		current = #inv.inventory.UnlockedPets
	elseif category == "cars" then
		current = #inv.inventory.UnlockedCars
	end
	return {
		ok = true,
		allowed = (current < limit),
		current = current,
		limit = limit,
	}
end

-- Añade un item a una categoría del inventario si hay espacio.
function AGACentralService:UnlockItem(userId, category, itemKey)
	userId = tostring(userId)
	local limit = (config.InventoryLimits or {})[category] or 50
	local inv = self:GetInventory(userId)
	if not inv.ok then return inv end
	local bucket = (category == "pets") and inv.inventory.UnlockedPets or inv.inventory.UnlockedCars
	local key = tostring(itemKey)
	for _, existing in ipairs(bucket) do
		if tostring(existing) == key then
			return { ok = true, added = false, reason = "duplicate" }
		end
	end
	if #bucket >= limit then
		return { ok = true, added = false, reason = "limit" }
	end
	table.insert(bucket, key)
	local upd = self:SaveInventory(userId, inv.inventory)
	if not upd.ok then return upd end
	return { ok = true, added = true, reason = "ok" }
end

-- Acredita monedas/trofeos al inventario global (acumulativo).
function AGACentralService:AddCoins(userId, amount)
	local inv = self:GetInventory(userId)
	if not inv.ok then return inv end
	inv.inventory.Coins = (inv.inventory.Coins or 0) + math.floor(tonumber(amount) or 0)
	return self:SaveInventory(userId, inv.inventory)
end

function AGACentralService:AddTrophies(userId, amount)
	local inv = self:GetInventory(userId)
	if not inv.ok then return inv end
	inv.inventory.Trophies = (inv.inventory.Trophies or 0) + math.floor(tonumber(amount) or 0)
	return self:SaveInventory(userId, inv.inventory)
end

-- ============================================================================
-- CÓDIGOS QR (AGA_Promotions — consumo GLOBAL)
-- ============================================================================

-- Busca la fila de un código en el backend central.
function AGACentralService:FindCode(code)
	code = tostring(code or ""):upper():gsub("%s+", "")
	if code == "" then return { ok = true, found = false, row = nil } end
	local q = queryRows(config.Tables.Promotions, {
		{ field = "Code", op = "eq", value = code },
	}, 1)
	if not q.ok then return q end
	if not q.found then return { ok = true, found = false, row = nil } end
	return { ok = true, found = true, row = q.rows[1] }
end

-- Verifica si un código ya fue canjeado (tiene dueño).
function AGACentralService:IsCodeClaimed(code)
	local res = self:FindCode(code)
	if not res.ok then return res end
	if not res.found then return { ok = true, claimed = false } end
	local row = res.row
	local owner = tostring(row["Roblox User Id"] or "")
	return {
		ok = true,
		claimed = (owner ~= ""),
		row = row,
	}
end

-- ============================================================================
-- CLAIM PRINCIPAL (lo que cada juego llama antes de otorgar)
-- params: { code, userId, username?, experience ("street"|"activation"),
--           placeId? (override del Place del juego) }
-- Respuesta:
--   { Success=true, Code=..., Reward=... }   → el juego acredita la recompensa
--   { Success=false, ErrorMessage="..." }    → mostrar al usuario (sin otorgar)
--
-- LA TRANSACCIÓN ES CENTRAL: el código se marca con el userId y Status
-- "3. Item Entregado" SOLO aquí; si el juego 2 consulta el mismo código
-- después, IsCodeClaimed/FindCode devuelve el dueño → rechazado.
-- ============================================================================
function AGACentralService:ClaimCode(params)
	if not config then return { Success = false, ErrorMessage = "AGACentral no inicializado." } end
	local code = tostring(params.code or ""):upper():gsub("%s+", "")
	local userId = tostring(params.userId or "")
	if code == "" or userId == "" then
		return { Success = false, ErrorMessage = "Código o usuario inválido." }
	end
	local experience = tostring(params.experience or "street")
	local placeId = tostring(params.placeId or "")
	if placeId == "" and config.Places[experience] then
		placeId = config.Places[experience].PlaceId
	end

	-- 1) ¿Existe el código y no está consumido?
	local found = self:FindCode(code)
	if not found.ok then
		return { Success = false, ErrorMessage = "No se pudo validar el código. Intenta de nuevo." }
	end
	if not found.found then
		return { Success = false, ErrorMessage = "El código ingresado no existe." }
	end
	local row = found.row
	local owner = tostring(row["Roblox User Id"] or "")
	if owner ~= "" and owner ~= userId then
		return { Success = false, ErrorMessage = "Este código ya ha sido reclamado previamente." }
	end

	-- 2) Anti-duplicado: si este mismo usuario ya lo reclamó (Status 3)
	local statusName = ""
	if type(row.Status) == "table" then
		statusName = tostring(row.Status.Name or "")
	else
		statusName = tostring(row.Status or "")
	end
	if statusName == "3. Item Entregado" and owner == userId then
		return { Success = false, ErrorMessage = "Este código ya ha sido reclamado previamente." }
	end

	-- 3) Consumir el código EN EL BACKEND (marcar dueño + status 3 + lugar)
	local now = os.date("!%Y-%m-%dT%H:%M:%SZ")
	local upd = mutate(config.Tables.Promotions, {
		type = "update",
		table = "t",
		set = {
			["Roblox User Id"] = userId,
			["Claimed At"] = now,
			["Source Place Id"] = placeId,
			Experience = experience,
			Status = "3. Item Entregado",
		},
		where = {
			{ field = "Code", op = "eq", value = code },
		},
	})
	if not upd.ok then
		return { Success = false, ErrorMessage = "No se pudo registrar el canje." }
	end

	-- 4) Devolver la recompensa de la relación (si existe en la fila leída)
	local reward = nil
	local rw = row.Reward
	if type(rw) == "table" then
		if rw[1] then
			reward = {
				Name = tostring(rw[1].Record or rw[1].Name or ""),
				Id = tostring(rw[1].Id or rw[1].ID or ""),
			}
		elseif type(rw.Name) == "string" then
			reward = { Name = rw.Name, Id = tostring(rw.Id or "") }
		end
	end

	return {
		Success = true,
		Code = code,
		Experience = experience,
		SourcePlaceId = placeId,
		Reward = reward,
		ClaimedAt = now,
	}
end

-- ============================================================================
-- UTILIDAD: inventario de un Player (wrapper)
-- ============================================================================
function AGACentralService:GetInventoryForPlayer(player)
	return self:GetInventory(player and player.UserId)
end

return AGACentralService
