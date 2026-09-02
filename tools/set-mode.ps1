<#
.SYNOPSIS
  Alterna el repositorio AGA entre "demo" (Add-On QR activo) y "entrega" (solo metricas).

.DESCRIPTION
  Edita las 2 fuentes de verdad de los feature flags:
    web/config.js               -> features.qrRedemptionEnabled / tenantSwitcherEnabled
    luau/AGAModuleConfig.lua    -> Modules.qrRedemption.Enabled
  Deja el repo listo para publicar. Recuerda que en Roblox (Studio) tambien hay que
  flipear AGAModuleConfig dentro de cada juego y republicar (ver docs/FEATURE_FLAGS.md).

.EXAMPLE
  pwsh tools/set-mode.ps1 demo     # habilita el modulo QR (presentacion)
  pwsh tools/set-mode.ps1 entrega  # deshabilita el modulo QR (entregable a AGA)
#>
param(
  [Parameter(Mandatory = $true, Position = 0)]
  [ValidateSet("demo", "entrega")]
  [string]$Mode
)
$ErrorActionPreference = "Stop"

$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$configJs = Join-Path $root "web\config.js"
$moduleLua = Join-Path $root "luau\AGAModuleConfig.lua"

if (-not (Test-Path -LiteralPath $configJs) -or -not (Test-Path -LiteralPath $moduleLua)) {
  Write-Error "No se encontraron web/config.js o luau/AGAModuleConfig.lua bajo $root"
}

$val = if ($Mode -eq "demo") { "true" } else { "false" }

function Set-Flag([string]$path, [string]$pattern, [string]$replacement) {
  $content = [System.IO.File]::ReadAllText($path)
  $new = [regex]::Replace($content, $pattern, $replacement)
  if ($new -ceq $content) {
    Write-Warning "[set-mode] El patron no matcheo en $path -> $pattern"
  }
  # UTF-8 sin BOM (compatible con Windows PowerShell 5.1 y pwsh 7)
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($path, $new, $utf8NoBom)
}

# web/config.js: solo la línea de la propiedad (no los comentarios)
Set-Flag $configJs '(?m)^(\s*qrRedemptionEnabled: )(true|false)(,?\s*)$' ('${1}' + $val + '${3}')
Set-Flag $configJs '(?m)^(\s*tenantSwitcherEnabled: )(true|false)(,?\s*)$' ('${1}' + $val + '${3}')
# luau/AGAModuleConfig.lua: conserva indentacion, llaves y "Enabled = "
Set-Flag $moduleLua '(qrRedemption = \{)(\s*)(Enabled = )(true|false)' ('${1}${2}${3}' + $val)

Write-Host ""
Write-Host "[set-mode] Repo AGA en modo: $Mode  (qrRedemption = $val)"
Write-Host "  web/config.js            -> qrRedemptionEnabled=$val  tenantSwitcherEnabled=$val"
Write-Host "  luau/AGAModuleConfig.lua -> Modules.qrRedemption.Enabled=$val"
Write-Host ""
Write-Host "Siguiente paso (deploy):"
Write-Host "  1) Web: subir config.js + paginas a la app de Praxsuite y publicar."
Write-Host "  2) Roblox: en CADA lobby (ServerScriptService.AGA_Racing) flipear AGAModuleConfig"
Write-Host "     al mismo valor y publicar el juego (ver docs/FEATURE_FLAGS.md)."
