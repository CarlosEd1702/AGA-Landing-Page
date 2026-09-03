# 🏁 AGA — Landing + QR centralizado (2 experiencias Roblox)

Plantilla base phygital para **AGA**: QR físico → elección de experiencia
(Carrera para Impresionar / Activación AGA) → Roblox con deep link → recompensa
acreditada en un **inventario centralizado** (Praxsuite) compartido por ambos juegos.

> ⚠️ **Repositorio PRIVADO**: referencia el WorkspaceId de Praxsuite y endpoints
> internos. No exponer.
>
> 🤖 **¿Sos un agente (DeepSeek/Claude)?** Leé [`AGENTS.md`](AGENTS.md) y
> [`docs/CONVENTIONS.md`](docs/CONVENTIONS.md) antes de tocar código.

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
│   ├── AGACentralService.lua    ← backend central compartido (RecordQRAttribution + gates)
│   ├── AGAGameSessionsService.lua ← sesiones de juego (AGA_Game_Sessions, 4 places) — NUEVO
│   ├── AGAQRRedeemService.lua   ← flujo server de reclamo (atribución demo, GrantReward preparado)
│   ├── LaunchQRController.lua   ← cliente deep link (maneja ModuleDisabled/Welcome)
│   └── QRRedeemController.lua   ← cliente canje manual (maneja ModuleDisabled/Welcome)
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
| **AGA_QR_Scans** | `562c913c-21a0-4759-8dfa-4ab8acb42eed` | Atribución de compra (escaneo de QR de botella → entrada a Roblox) |
| **AGA_Game_Sessions** | `dd29d762-7e41-419b-b394-8259b8225dfc` | Sesiones de juego de los 4 places (heatmap/duración/concurrencia) |

Endpoints (Sync, sin auth):
- **AGA Dashboard** `…/endpoint/b8023eb1-f4dd-4581-9598-0149d22fef7f` — conversión QR + engagement (reporte.html nuevo).
- **AGA QR Scan Register** `…/endpoint/863a5932-b44b-4f27-ab2f-1860e4b3d6ff` — lo llama la landing al escanear.
- **AGA Live Stats** `…/endpoint/42064538-6bc8-4e6f-a386-070d929a9220` — reporte anterior (KPIs + canjes).

## Pendiente antes de producción

- [ ] `ApiKey` readwrite AGA en `AGACentralService.lua` (o Secret)
- [ ] Publicar páginas en una App de Praxsuite (`aga-…`) con `config.js`
- [ ] Replicar `AGAModuleConfig` + módulos actualizados en ambos juegos Roblox
- [ ] Para la entrega: flags en `false` (ver `docs/FEATURE_FLAGS.md`)

Detalle completo: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) ·
[`docs/FEATURE_FLAGS.md`](docs/FEATURE_FLAGS.md)
