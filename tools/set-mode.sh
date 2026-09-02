#!/usr/bin/env bash
# Alterna el repositorio AGA entre "demo" (Add-On QR activo) y "entrega" (solo metricas).
# Edita web/config.js y luau/AGAModuleConfig.lua (fuentes de verdad de los feature flags).
# Uso:  ./tools/set-mode.sh demo | entrega
set -euo pipefail

MODE="${1:-}"
case "$MODE" in
  demo|entrega) ;;
  *) echo "Uso: $0 demo|entrega" >&2; exit 1 ;;
esac

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG_JS="$ROOT/web/config.js"
MODULE_LUA="$ROOT/luau/AGAModuleConfig.lua"

VAL="true"; [ "$MODE" = "entrega" ] && VAL="false"

perl -0pi -e "s/(qrRedemptionEnabled: )(true|false)/\${1}${VAL}/" "$CONFIG_JS"
perl -0pi -e "s/(tenantSwitcherEnabled: )(true|false)/\${1}${VAL}/" "$CONFIG_JS"
perl -0pi -e "s/(qrRedemption = \{\s*Enabled = )(true|false)/\${1}${VAL}/" "$MODULE_LUA"

echo ""
echo "[set-mode] Repo AGA en modo: $MODE  (qrRedemption = $VAL)"
echo "  web/config.js            -> qrRedemptionEnabled=$VAL  tenantSwitcherEnabled=$VAL"
echo "  luau/AGAModuleConfig.lua -> Modules.qrRedemption.Enabled=$VAL"
echo ""
echo "Siguiente paso (deploy):"
echo "  1) Web: subir config.js + paginas a la app de Praxsuite y publicar."
echo "  2) Roblox: en CADA lobby (ServerScriptService.AGA_Racing) flipear AGAModuleConfig"
echo "     al mismo valor y publicar el juego (ver docs/FEATURE_FLAGS.md)."
