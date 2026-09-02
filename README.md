# 🏁 AGA — Landing + QR centralizado (2 experiencias Roblox)

Plantilla base phygital para **AGA**: QR físico → elección de experiencia
(Carrera para Impresionar / Activación AGA) → Roblox con deep link → recompensa
acreditada en un **inventario centralizado** (Praxsuite) compartido por ambos juegos.

> ⚠️ **Repositorio PRIVADO**: referencia el WorkspaceId de Praxsuite y endpoints
> internos. No exponer.

## 🚦 Módulos y Feature Flags (Demo ⇄ Entrega)

El contrato de AGA incluye **solo el Dashboard de Métricas** (`reporte.html`).
El **canje por QR** es un **Add-On de pago** que se demuestra con un feature flag.
**El estado por defecto de `main` es ENTREGA** (flags en `false`).

| Flag | Demo Interna | Entrega a AGA |
|---|---|---|
| `qrRedemptionEnabled` (web) / `qrRedemption.Enabled` (Roblox) | `true` | `false` |
| `analyticsDashboardEnabled` | `true` | `true` (entregable) |
| `tenantSwitcherEnabled` (reporte) | `true` (uso interno) | `false` (fijo AGA) |

**Cambiar de modo con UN comando** (edita web + luau, sin tocar nada a mano):

```powershell
pwsh tools/set-mode.ps1 demo      # habilita el Add-On QR (presentación)
pwsh tools/set-mode.ps1 entrega   # lo desactiva (entregable a AGA)
```

**Ver [`docs/FEATURE_FLAGS.md`](docs/FEATURE_FLAGS.md)** — runbook de la demo,
cómo alternar modos y dónde vive cada bandera (web `config.js` + Roblox
`AGAModuleConfig.lua`).

## Estructura

```
├── web/
│   ├── config.js         ← Feature flags web (fuente de UI) — NUEVO
│   ├── index.html        ← Landing dual: Vista Demo (canje) / Vista Entrega (institucional)
│   ├── reporte.html      ← Entregable principal: Dashboard de métricas (independiente)
│   ├── qr.html           ← Galería QR (solo visible con el Add-On activo)
│   └── js/deep-link-handler.js  ← handler deep link (copia de Electrolit)
├── luau/
│   ├── AGAModuleConfig.lua      ← Feature flags server-side (Roblox) — NUEVO
│   ├── AGACentralService.lua    ← backend central compartido (gate qrRedemption)
│   ├── AGAQRRedeemService.lua   ← flujo server de reclamo (gate qrRedemption)
│   ├── LaunchQRController.lua   ← cliente deep link (maneja ModuleDisabled)
│   └── QRRedeemController.lua   ← cliente canje manual (maneja ModuleDisabled)
├── tools/
│   ├── set-mode.ps1             ← toggle Demo ⇄ Entrega (Windows/PowerShell) — NUEVO
│   └── set-mode.sh              ← toggle Demo ⇄ Entrega (bash) — NUEVO
├── docs/
│   ├── FEATURE_FLAGS.md   ← sistema de flags + runbook Demo ⇄ Entrega — NUEVO
│   └── ARCHITECTURE.md    ← esquema SQL/JSON, endpoints, checklist
```

## Backend Praxsuite (ya creado)

| Tabla | UUID | Rol |
|---|---|---|
| AGA_Promotions | `44f07e3b-94a0-4837-b475-343c5e29ab94` | Códigos QR (consumo global) |
| AGA_Inventories | `8105d853-ffe8-448d-815b-3960ddbc7edc` | Inventario global del jugador |
| AGA_ScanEvents | `74c74a66-6c8f-443b-9d8e-ce964435434b` | Aperturas de QR (métricas) |
| AGA_Rewards | `29b7f8fe-550c-40c4-975d-788645df339f` | Catálogo de recompensas |

Endpoint **AGA Live Stats** (reporte): `…/endpoint/42064538-6bc8-4e6f-a386-070d929a9220`
(POST `{companyId:"aga", experience:"all"|"street"|"activation"}`) — verificado ✓

## Pendiente antes de producción

- [ ] `ApiKey` readwrite AGA en `AGACentralService.lua` (o Secret)
- [ ] Publicar páginas en una App de Praxsuite (`aga-…`) con `config.js`
- [ ] Replicar `AGAModuleConfig` + módulos actualizados en ambos juegos Roblox
- [ ] Para la entrega: flags en `false` (ver `docs/FEATURE_FLAGS.md`)

Detalle completo: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) ·
[`docs/FEATURE_FLAGS.md`](docs/FEATURE_FLAGS.md)
