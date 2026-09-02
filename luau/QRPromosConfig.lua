--[[
================================================================================
 QRPromosConfig — Lote de códigos promocionales AGA (compartido entre juegos)
================================================================================
 companyId = "aga"
 Experiencias: "street" (Carrera para Impresionar) | "activation" (Activación AGA)

 REEMPLAZA el config de Electrolit pero con el claim CENTRALIZADO: la fuente de
 verdad de consumo es AGA_Promotions en Praxsuite (AGACentralService:ClaimCode).
 Este módulo solo define QUÉ entrega cada código (recompensas) y sirve para la
 validación rápida server-side ANTES de llamar al backend central.

 Por ahora las recompensas son SOLO monetarias (Coins del juego). La estructura
 ya deja preparado el campo "Items" para cuando se soporten objetos 3D (autos/
 cosméticos) sin romper el esquema.

 USO (server-side):
   local QRPromosConfig = require(ReplicatedStorage.AGA_Racing.Modules.QRPromosConfig)
   local reward = QRPromosConfig.GetReward("AGA-2026-0001")  -- { Coins=500, Items={} }
================================================================================
]]

local QRPromosConfig = {}

-- Recompensa única: monedas (amount) + items futuros (array vacío por ahora).
-- `exp` indica a qué experiencia pertenece el código (para el registro central).
local CODES = {
	-- === Lote demo "Carrera para Impresionar" (street) ===
	{ Code = "AGA-2026-0001", Exp = "street",     Coins = 500,  Items = {} },
	{ Code = "AGA-2026-0002", Exp = "street",     Coins = 1000, Items = {} },
	{ Code = "AGA-2026-0003", Exp = "street",     Coins = 1500, Items = {} },
	-- === Lote demo "Activación AGA" (activation) ===
	{ Code = "AGA-2026-0004", Exp = "activation", Coins = 500,  Items = {} },
	{ Code = "AGA-2026-0005", Exp = "activation", Coins = 1000, Items = {} },
	{ Code = "AGA-2026-0006", Exp = "activation", Coins = 1500, Items = {} },
}

-- Índice normalizado code → reward (case-insensitive)
local BY_CODE = {}
for _, entry in ipairs(CODES) do
	BY_CODE[tostring(entry.Code):upper():gsub("%s+", "")] = entry
end

-- Devuelve la recompensa de un código (o nil si no existe).
-- Normaliza: mayúsculas y sin espacios.
function QRPromosConfig.GetReward(code)
	local key = tostring(code or ""):upper():gsub("%s+", "")
	local entry = BY_CODE[key]
	if not entry then return nil end
	return {
		Coins = math.floor(tonumber(entry.Coins) or 0),
		Items = entry.Items or {},
		Exp = entry.Exp,
		Code = entry.Code,
	}
end

-- Devuelve la lista completa (para minting/dashboard interno si hiciera falta).
function QRPromosConfig.GetAll()
	local out = {}
	for _, e in ipairs(CODES) do
		table.insert(out, {
			Code = e.Code, Exp = e.Exp,
			Coins = math.floor(tonumber(e.Coins) or 0),
			Items = e.Items or {},
		})
	end
	return out
end

return QRPromosConfig
