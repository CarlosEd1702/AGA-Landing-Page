--[[
==============================================================================
 AGAModuleConfig — Feature Flags del módulo AGA (server-side)
==============================================================================
 Empresa: AGA (companyId = "aga")

 Fuente de verdad SERVER-SIDE de qué módulos contratados por AGA están activos.
 La web (estática) no puede leerse desde Roblox, así que la MISMA bandera lógica
 se replica en:
     web/config.js   → window.AGA_CONFIG.features.qrRedemptionEnabled
     este archivo    → Modules.qrRedemption.Enabled
 Cambiar SIEMPRE ambos con el mismo valor (ver docs/FEATURE_FLAGS.md).

    ┌─────────────────────────┬──────────────┬───────────────────────────────┐
    │ Módulo                  │ DEMO INTERNA │ ENTREGA A AGA                 │
    ├─────────────────────────┼──────────────┼───────────────────────────────┤
    │ qrRedemption (Add-On)   │ true         │ false  (no contratado)        │
    │ analyticsDashboard      │ true         │ true   (contratado)           │
    └─────────────────────────┴──────────────┴───────────────────────────────┘

 ENFORCEMENT (server-authoritative):
   AGACentralService:ClaimCode  y  AGAQRRedeemService:claimForPlayer  consultan
   IsModuleEnabled("qrRedemption") ANTES de tocar Praxsuite. Si el módulo está
   apagado responden { Success=false, ModuleDisabled=true, ... } sin escribir
   nada en el backend ni romper la sesión del jugador.

 NOTA DE DESPLIEGUE:
   Este módulo debe existir en ServerScriptService (junto a AGACentralService)
   de los juegos DONDE se quiera enforce el flag. Si el archivo no existe en un
   juego, los servicios operan con el flag habilitado por defecto (compatibilidad
   con instalaciones previas); para la entrega final a AGA hay que insertarlo
   con qrRedemption.Enabled = false y republicar.
==============================================================================
]]

local AGAModuleConfig = {
	CompanyId = "aga",

	Modules = {
		-- ── Módulo Add-On: "Reclamo por QR / canje de códigos" ──────────────
		-- true  → Demo interna / presentación técnica.
		-- false → Entrega a AGA: el servidor IGNORA cualquier intento de canje.
		-- ESTADO POR DEFECTO DEL REPO (main) = ENTREGA → false.
		-- Para demo: pwsh tools/set-mode.ps1 demo (o bash tools/set-mode.sh demo).
		qrRedemption = {
			Enabled = false, -- ⚠️ SINCRONIZAR con web/config.js
		},

		-- ── Módulo contratado: "Dashboard de Métricas y Reportes" ────────────
		-- Siempre true (es el entregable principal de AGA).
		analyticsDashboard = {
			Enabled = true,
		},
	},
}

-- Devuelve si un módulo está habilitado. Desconocido → false (fail-closed).
function AGAModuleConfig.IsModuleEnabled(moduleKey: string): boolean
	local module = AGAModuleConfig.Modules and AGAModuleConfig.Modules[moduleKey]
	if not module then
		return false
	end
	return module.Enabled == true
end

-- Devuelve true si el módulo de canje QR está ACTIVO (Add-On contratado/demo).
function AGAModuleConfig.IsQRRedemptionEnabled(): boolean
	return AGAModuleConfig.IsModuleEnabled("qrRedemption")
end

-- Devuelve true si el dashboard/reporte está activo (contratado por AGA).
function AGAModuleConfig.IsAnalyticsDashboardEnabled(): boolean
	return AGAModuleConfig.IsModuleEnabled("analyticsDashboard")
end

return AGAModuleConfig
