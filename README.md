# 🏁 AGA — Landing + QR centralizado (2 experiencias Roblox)

Plantilla base phygital para **AGA**: QR físico → elección de experiencia
(Carrera para Impresionar / Activación AGA) → Roblox con deep link → recompensa
acreditada en un **inventario centralizado** (Praxsuite) compartido por ambos juegos.

> ⚠️ **Repositorio PRIVADO**: referencia el WorkspaceId de Praxsuite y endpoints
> internos. No exponer.

## Estructura

```
├── web/
│   ├── index.html        ← Landing AGA (selector de 2 experiencias + deep link)
│   ├── reporte.html      ← Reporte multi-tenant (Logrus/AGA) + filtro por experiencia
│   ├── qr.html           ← (pendiente: galería de QR del lote AGA)
│   └── js/deep-link-handler.js  ← handler deep link (copia de Electrolit)
├── luau/
│   └── AGACentralService.lua   ← módulo central compartido por ambos juegos
├── docs/
│   └── ARCHITECTURE.md   ← esquema SQL/JSON, endpoints, checklist de replicación
└── assets/qr/            ← PNG del lote (generar con docs/generate-qr-codes.js de Electrolit)
```

## Backend Praxsuite (ya creado)

| Tabla | UUID | Rol |
|---|---|---|
| AGA_Promotions | `44f07e3b-94a0-4837-b475-343c5e29ab94` | Códigos QR (consumo global) |
| AGA_Inventories | `8105d853-ffe8-448d-815b-3960ddbc7edc` | Inventario global del jugador |
| AGA_ScanEvents | `74c74a66-6c8f-443b-9d8e-ce964435434b` | Aperturas de QR (métricas) |
| AGA_Rewards | `29b7f8fe-550c-40c4-975d-788645df339f` | Catálogo de recompensas |

Endpoint **AGA Live Stats**: `…/endpoint/42064538-6bc8-4e6f-a386-070d929a9220`
(POST `{companyId:"aga", experience:"all"|"street"|"activation"}`) — verificado ✓

## Pendiente antes de producción

- [ ] PlaceId real de "Activación AGA" (en `web/index.html` y `luau/AGACentralService.lua`)
- [ ] `ApiKey` readwrite AGA en `AGACentralService.lua` (o Secret)
- [ ] Publicar páginas en una App de Praxsuite (`aga-…`)
- [ ] Mintear lote `AGA-2026-…` y generar PNG
- [ ] Incluir `AGACentralService` en ambos juegos y cablear `ClaimQRRemote`

Detalle completo: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
