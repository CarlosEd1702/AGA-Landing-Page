/**
 * ============================================================================
 *  AGA · Configuración central de módulos (Feature Flags) — fuente web
 * ============================================================================
 *  Empresa: AGA (companyId: "aga")
 *
 *  Este archivo es la ÚNICA fuente de verdad de la capa web para decidir qué
 *  módulos contratados por AGA están visibles/activos:
 *
 *    ┌─────────────────────────────┬───────────────────┬──────────────────────┐
 *    │ Módulo                      │ DEMO INTERNA      │ ENTREGA A AGA        │
 *    ├─────────────────────────────┼───────────────────┼──────────────────────┤
 *    │ qrRedemptionEnabled         │ true              │ false                │
 *    │ (Canje por QR / Reclamo)    │ (Add-On en demo)  │ (No contratado)      │
 *    ├─────────────────────────────┼───────────────────┼──────────────────────┤
 *    │ analyticsDashboardEnabled   │ true              │ true                 │
 *    │ (Dashboard y Reporte)       │                   │ (CONTRATADO —        │
 *    │                             │                   │  entregable principal)│
 *    └─────────────────────────────┴───────────────────┴──────────────────────┘
 *
 *  ⚠️  SINCRONIZACIÓN con Roblox:
 *  La web (estática) y los juegos de Roblox no comparten runtime. La MISMA
 *  bandera lógica debe reflejarse en el servidor del juego para que el
 *  enforcement sea real (server-authoritative), en:
 *      luau/AGAModuleConfig.lua   (Modules.qrRedemption.Enabled)
 *  Cambiar SIEMPRE ambos archivos con el mismo valor.
 *
 *  USO: cargar ANTES que los scripts de la página (síncrono, sin defer):
 *      <script src="config.js"></script>
 *  Expone window.AGA_CONFIG (ver getConfig() abajo).
 * ============================================================================
 */

var AGA_CONFIG = {
  companyId: "aga",
  companyName: "AGA",

  features: {
    // ── Módulo Add-On: "Reclamo por QR / canje de códigos" ──────────────────
    // true  → Demo interna / presentación técnica (interfaz de canje completa).
    // false → Entrega a AGA: se oculta TODO el flujo de canje (index muestra una
    //         landing institucional; qr.html queda bloqueado con aviso).
    // ESTADO POR DEFECTO DEL REPO (main) = ENTREGA → false.
    // Para demo: pwsh tools/set-mode.ps1 demo (o bash tools/set-mode.sh demo).
    qrRedemptionEnabled: true,

    // ── Módulo contratado: "Dashboard de Métricas y Reportes" ───────────────
    // Entregable principal de AGA (reporte.html). Se mantiene SIEMPRE true.
    analyticsDashboardEnabled: true,

    // ── Selector multi-tenant del reporte (AGA / Logrus) ────────────────────
    // true  → uso INTERNO del equipo: el reporte permite cambiar de empresa.
    // false → entregable limpio a AGA: el reporte queda fijado en companyId "aga".
    // ESTADO POR DEFECTO DEL REPO (main) = ENTREGA → false (reporte fijo AGA).
    tenantSwitcherEnabled: true,
  },

  // Empresas disponibles en el reporte (solo si tenantSwitcherEnabled === true).
  tenants: {
    aga: { label: "⚫ AGA (AGA_*)", endpoint: "https://gateway.praxsuite.com/cc6ac8fa-e31c-421d-99af-15951a0e8a7a/endpoint/42064538-6bc8-4e6f-a386-070d929a9220" },
    logrus: { label: "🔴 Logrus (LGR_*)", endpoint: "https://gateway.praxsuite.com/cc6ac8fa-e31c-421d-99af-15951a0e8a7a/endpoint/b3b14430-daab-46e5-b6e3-46ac32526a37" },
  },
};

/**
 * getConfig() — acceso tolerante a recarga: si la página ya definió un override
 * (p. ej. vía query string en una demo), lo respeta; si no, devuelve AGA_CONFIG.
 */
function getConfig() {
  return (typeof window !== "undefined" && window.AGA_CONFIG) || AGA_CONFIG;
}

if (typeof window !== "undefined") {
  window.AGA_CONFIG = AGA_CONFIG;
  // Helper global para las páginas (index / qr / reporte).
  window.AGA = {
    config: AGA_CONFIG,
    isQRRedemptionEnabled: function () {
      return !!(AGA_CONFIG.features && AGA_CONFIG.features.qrRedemptionEnabled);
    },
    isAnalyticsDashboardEnabled: function () {
      return !!(AGA_CONFIG.features && AGA_CONFIG.features.analyticsDashboardEnabled);
    },
    isTenantSwitcherEnabled: function () {
      return !!(AGA_CONFIG.features && AGA_CONFIG.features.tenantSwitcherEnabled);
    },
  };
}
