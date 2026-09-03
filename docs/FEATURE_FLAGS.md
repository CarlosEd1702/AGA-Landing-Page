# AGA · Feature Flags (Módulos contratados vs Add-On en Demo)

> **Contexto de negocio**: el cliente AGA contrató únicamente el **Dashboard de
> Métricas y Reportes** (`reporte.html`). El **Reclamo por QR / canje de códigos**
> es un módulo **Add-On de pago** que NO forma parte del contrato actual.
>
> Para la **Demostración Técnica** se habilita el Add-On en un entorno de prueba;
> para la **entrega final** el módulo queda desactivado y solo se ve el reporte.

## 🎛️ Cambio de modo con UN comando (recomendado)

El estado por defecto del repo (`main`) es **ENTREGA** (solo métricas). Para
alternar no hace falta editar nada a mano:

```powershell
# Windows / PowerShell
pwsh tools/set-mode.ps1 demo      # habilita el módulo QR (presentación)
pwsh tools/set-mode.ps1 entrega   # lo desactiva (entregable a AGA)

# bash / macOS / Linux
./tools/set-mode.sh demo
./tools/set-mode.sh entrega
```

El script edita las 2 fuentes de verdad (web + luau) con el mismo valor y te
recuerda los pasos de deploy (subir web + flipear los lobbies en Studio).

---

## 1) ¿Dónde vive cada bandera? (2 fuentes espejo)

La web (HTML estático) y los juegos de Roblox **no comparten runtime**, por lo que
la misma bandera lógica se declara en dos archivos que deben mantenerse en sync:

| Capa | Archivo | Campo |
|---|---|---|
| **Web** (UI: index / qr / reporte) | `web/config.js` | `features.qrRedemptionEnabled` |
| **Roblox** (server, enforcement) | `luau/AGAModuleConfig.lua` *(insertado en ServerScriptService de cada juego)* | `Modules.qrRedemption.Enabled` |

```
┌───────────────────────────┬───────────────────────┬──────────────────────────┐
│ Módulo                    │ DEMO INTERNA          │ ENTREGA A AGA            │
├───────────────────────────┼───────────────────────┼──────────────────────────┤
│ qrRedemption (Add-On)     │ true                  │ false                    │
│ analyticsDashboard        │ true                  │ true  (entregable)       │
│ tenantSwitcher (reporte)  │ true (uso interno)    │ false (reporte fijo AGA) │
└───────────────────────────┴───────────────────────┴──────────────────────────┘
```

---

## 2) Qué hace cada bandera

### `qrRedemptionEnabled` (web) — `Modules.qrRedemption.Enabled` (Roblox)

**Web (`web/config.js`)**
- `true` → `index.html` renderiza la **Vista Demo**: input de canje manual,
  selector de experiencia, botones deep-link con `launchData={qrCode,...}` y
  acceso a `qr.html` (galería).
- `false` → `index.html` renderiza la **Vista Entrega**: landing institucional
  limpia enfocada a las 2 experiencias Roblox (deep link **sin** código) + botón
  destacado **"Ver métricas y reporte"**. `qr.html` muestra un aviso de módulo no
  contratado y oculta la galería. El nav de `reporte.html` oculta "Códigos QR".

**Roblox (`luau/AGAModuleConfig.lua`, server-side)**
- `true` → los servicios procesan canjes con normalidad.
- `false` → **enforcement server-authoritative**: `AGACentralService:ClaimCode`
  y `AGAQRRedeemService:claimForPlayer` responden
  `{ Success=false, ModuleDisabled=true, ErrorMessage="El canje por QR no está
  disponible en esta experiencia." }` **sin tocar Praxsuite** (no consumen
  códigos, no escriben nada). Los clientes (`LaunchQRController`,
  `QRRedeemController`) muestran un aviso interno discreto y **no rompen la
  experiencia** del jugador.

> 🔒 **Regla de seguridad**: aunque la web (o un tercero) envíe un `launchData`
> con código, el servidor de Roblox valida la bandera del módulo ANTES de
> procesar el reclamo. Nunca confiar en el cliente.

### `analyticsDashboardEnabled`
Bandera del entregable contratado (reporte). Hoy siempre `true`; si algún día se
apaga, `reporte.html` puede mostrar un aviso. No afecta a Roblox.

### `tenantSwitcherEnabled` (solo reporte)
- `true` → el reporte muestra el selector **AGA / Logrus** (uso interno del equipo).
- `false` → **entregable limpio**: el reporte queda fijado en `companyId="aga"`
  (se oculta la barra de empresa; el filtro por experiencia AGA se mantiene).

---

## 3) Cómo cambiar entre "Modo Demo QR" y "Modo Producción Entregable"

> ✅ **Estado por defecto del repo (`main`) = ENTREGA** (flags en `false`).
> Para la demo usá el toggle de la sección 1 y commiteá el cambio SOLO si querés
> dejar `main` en demo (no recomendado: `main` debe ser siempre el entregable).

### ▶ Activar Demo (presentación técnica)
1. **Automático**: `pwsh tools/set-mode.ps1 demo` (edita `web/config.js` +
   `luau/AGAModuleConfig.lua` en `true`). También podés editar a mano:
   `web/config.js` → `qrRedemptionEnabled: true` (y `tenantSwitcherEnabled: true`
   si querés el selector interno en el reporte).
2. **Roblox (cada juego, 2 lobbies)**: en `ServerScriptService.AGA_Racing` →
   `AGAModuleConfig`, poner `qrRedemption.Enabled = true` y **publicar** el juego
   (File → Publish to Roblox / versión de producción).
3. Subir `config.js`, `index.html`, `qr.html`, `reporte.html` a la app web
   (`aga-*.praxsuite.app`) y publicar páginas.

### ■ Desactivar para Entrega a AGA
1. **Automático**: `pwsh tools/set-mode.ps1 entrega`. Manual: `web/config.js` →
   `qrRedemptionEnabled: false`, `tenantSwitcherEnabled: false`.
2. **Roblox (ambos lobbies)**: `qrRedemption.Enabled = false` + publicar.
3. Opcional (recomendado): quitar/ocultar la `QRRedeemGui` / `PromoRewardGui` /
   `HintGui` de StarterGui y el hint "Presiona R" para que el jugador de la
   entrega ni vea la UI de canje. El enforcement del servidor sigue activo aunque
   la UI exista.
4. Subir + publicar la web. Resultado: `index.html` institucional + `reporte.html`
   como entregable único de métricas.

---

## 4) Runbook de la Demo Técnica (sesión con AGA)

> **Demo comercial 2026-09-02**: el QR SÍ se muestra y funciona de punta a punta
> (landing + Roblox), pero **NO entrega recompensa** por ahora. Al entrar registra
> la atribución en `AGA_QR_Scans` (Status "2. Ingresó al Juego") y la UI muestra
> *"¡Bienvenido desde la promoción AGA!"*. El claim con recompensa queda cableado
> (`GrantReward()` preparado) para cuando AGA decida activarlo.

| # | Paso | Dónde | Qué se ve |
|---|---|---|---|
| 1 | Verificar `qrRedemptionEnabled=true` (web y Roblox) | `config.js` + `AGAModuleConfig` | — |
| 2 | Escanear un QR de `qr.html` (o abrir su URL) | celular / navegador | URL directa `https://www.roblox.com/games/<PLACE_ID>/?launchData=AGA_BOTTLE_PROMO` (sin 404) |
| 3 | Roblox recibe el token plano de campaña | Lobby | Welcome "¡Bienvenido desde la promoción AGA!" (sin +Coins) |
| 4 | El servidor registra la atribución | Lobby (server) | `AGA_QR_Scans` → Status "2. Ingresó al Juego" + UserId (source bottle_qr) |
| 5 | (Alternativo) Ingresar un código del lote en `index.html` | Navegador | Deep link JSON → mismo welcome/atribución |
| 6 | Abrir `reporte.html` | Navegador (otra pestaña) | Sección A (conversión QR, demo) + Sección B (engagement REAL de telemetría) — auto-refresh 15 s |
| 7 | Cerrar la demo | — | Poner flags en `false` (sección 3) y republicar |

> **Nota**: `reporte.html` consume el endpoint **AGA Dashboard**
> (`b8023eb1-…`). Sección A = conversión QR (`AGA_QR_Scans`, demo simulada para
> el pitch). Sección B = **datos REALES** (`AGA_RaceSessions` +
> `AGA_RaceParticipants` + `AGA_DailyRaceSummary`: heatmap día×hora, duración por
> experiencia, flujo por hora, activos por día).

### Chequeo rápido del enforcement (Roblox, Server)

```lua
-- En ServerScriptService (consola de Studio, modo Server):
local AGAModuleConfig = require(ServerScriptService.AGA_Racing.AGAModuleConfig)
print(AGAModuleConfig.IsQRRedemptionEnabled()) -- true=demo | false=entrega
```

Si está en `false` y un cliente intenta canjear:
`ClaimQRRemote` responde `ModuleDisabled=true` → la UI muestra el aviso y **no**
se consume nada en Praxsuite.

---

## 5) Archivos tocados por este sistema

```
web/config.js                 ← NUEVO: feature flags web (fuente de UI)
web/index.html                ← dual-mode: Vista Demo (canje) / Vista Entrega (landing)
web/qr.html                   ← gate: si flag off → aviso "módulo no contratado"
web/reporte.html              ← entregable independiente + nav/tenant dinámicos
luau/AGAModuleConfig.lua      ← NUEVO: feature flags server-side (fuente Roblox)
luau/AGACentralService.lua    ← gate qrRedemption en ClaimCode (defensa central)
luau/AGAQRRedeemService.lua   ← gate qrRedemption en claimForPlayer
luau/LaunchQRController.lua   ← maneja ModuleDisabled (aviso interno, sin romper)
luau/QRRedeemController.lua   ← maneja ModuleDisabled (aviso interno, sin romper)
tools/set-mode.ps1            ← NUEVO: toggle Demo ⇄ Entrega (Windows/PowerShell)
tools/set-mode.sh             ← NUEVO: toggle Demo ⇄ Entrega (bash)
tools/check-qr-links.js       ← NUEVO: verificación de QR/links (PlaceIds + HTTP 200, sin 404)
docs/FEATURE_FLAGS.md         ← este documento
```

**En Roblox (por cada juego, actualmente 2 lobbies AGA)**, replicar:
`AGAModuleConfig` (nuevo ModuleScript en `ServerScriptService.AGA_Racing`) y las
versiones actualizadas de `AGACentralService`, `AGAQRRedeemService`,
`LaunchQRController`, `QRRedeemController`.
