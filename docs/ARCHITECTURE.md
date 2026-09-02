# AGA — Arquitectura centralizada (2 experiencias Roblox)

> companyId: `"aga"` · Workspace Praxsuite: `cc6ac8fa-e31c-421d-99af-15951a0e8a7a`

## Visión

Dos experiencias independientes en Roblox comparten **un solo backend**:

| Experience key | Nombre | PlaceId |
|---|---|---|
| `street` | Carrera para Impresionar (Street Track) | `108987866733849` (TODO confirmar) |
| `activation` | Activación AGA (eventos privados) | TODO rellenar |

Regla de negocio: un código QR canjeado en **cualquiera** de los dos juegos queda
**consumido globalmente**; la recompensa se acredita en el **inventario global**
del usuario (visible/usable en ambas experiencias).

---

## 1) Esquema de datos (conceptual SQL ↔ Praxsuite)

### `aga_promotions` → tabla `AGA_Promotions` (`44f07e3b-94a0-4837-b475-343c5e29ab94`)

```sql
CREATE TABLE aga_promotions (
  code_id          VARCHAR PRIMARY KEY,  -- Praxsuite: Code (ShortText, key)
  company_id       VARCHAR DEFAULT 'aga',-- Praxsuite: Company
  experience       VARCHAR,              -- street | activation  (Praxsuite: Experience)
  is_redeemed      BOOLEAN DEFAULT FALSE,-- Praxsuite: Status status-column (1. Escaneado → 4. Jugó)
  claimed_by_user  VARCHAR,              -- Praxsuite: Roblox User Id
  claimed_at       TIMESTAMP,            -- Praxsuite: Claimed At (ISO 8601)
  source_place_id  VARCHAR,              -- Praxsuite: Source Place Id
  reward_id        VARCHAR REFERENCES aga_rewards -- Praxsuite: Reward (relación → AGA_Rewards)
);
```

### `aga_inventories` → tabla `AGA_Inventories` (`8105d853-ffe8-448d-815b-3960ddbc7edc`)

```sql
CREATE TABLE aga_inventories (
  user_id         VARCHAR PRIMARY KEY,   -- Praxsuite: Roblox User Id (key)
  username        VARCHAR,               -- Praxsuite: Username
  coins           INT DEFAULT 0,         -- Praxsuite: Coins
  trophies        INT DEFAULT 0,         -- Praxsuite: Trophies
  unlocked_pets   JSON DEFAULT '[]',     -- Praxsuite: Unlocked Pets (LongText JSON array)
  unlocked_cars   JSON DEFAULT '[]',     -- Praxsuite: Unlocked Cars (LongText JSON array)
  last_seen       TIMESTAMP              -- Praxsuite: Last Seen
);
```

### Catálogo y eventos

| Tabla | UUID | Rol |
|---|---|---|
| `AGA_Rewards` | `29b7f8fe-550c-40c4-975d-788645df339f` | Catálogo de recompensas (Item Type: Car/Pet/Cosmetic/Coins/Trophy; Rarity) |
| `AGA_ScanEvents` | `74c74a66-6c8f-443b-9d8e-ce964435434b` | 1 fila por apertura de QR (métricas) |

---

## 2) Endpoints (Sync, sin auth — para la web del QR)

| Endpoint | Método/Body | Función |
|---|---|---|
| **AGA Live Stats** (`42064538-6bc8-4e6f-a386-070d929a9220`) | POST `{companyId:"aga", experience:"all"\|"street"\|"activation"}` | KPIs + serie diaria + **byExperience** (comparativa) + últimos canjes. Rechaza companyId ≠ aga. |
| AGA QR Scan Register *(plantilla — clonar de EAS `0b62bc9c`)* | POST `{code, companyId, experience, placeId}` | Registra apertura en `AGA_ScanEvents` + upsert `AGA_Promotions` Status 1 |
| AGA QR Mint *(plantilla — clonar de EAS `f43bce3d`)* | POST `{prefix, count, experience}` | Genera lote de códigos en `AGA_Promotions` |

> **Nota anti-carrera entre juegos**: el consumo del código ocurre **en el backend**
> (update `AGA_Promotions` con `Roblox User Id` + Status "3. Item Entregado") — cada
> juego solo consulta `AGACentralService:ClaimCode`, que valida y consume en una
> operación; el segundo juego que consulte el mismo código recibirá "ya reclamado".

---

## 3) Módulo Luau compartido

`luau/AGACentralService.lua` — ModuleScript autocontenido (HttpService → API REST
de Praxsuite, sin SDK interno). Incluirlo en `ServerScriptService` de **ambos** juegos.

```lua
local AGACentral = require(ServerScriptService.AGACentralService)
AGACentral:Init({ ApiKey = "sk_live_...", Places = { street = { PlaceId = "..." }, activation = { PlaceId = "..." } } })

-- Claim (valida + consume global + anti-duplicado)
local res = AGACentral:ClaimCode({ code = "AGA-2026-0001", userId = tostring(player.UserId), experience = "street", placeId = tostring(game.PlaceId) })
-- res.Success / res.ErrorMessage / res.Reward

-- Inventario global (ambos juegos ven lo mismo)
local inv = AGACentral:GetInventory(player.UserId)          -- crea fila si no existe
AGACentral:AddCoins(player.UserId, 500)
AGACentral:AddTrophies(player.UserId, 1)
AGACentral:UnlockItem(player.UserId, "cars", "AGA-Turbo-01") -- respeta límite

-- Límite compartido
local lim = AGACentral:CheckInventoryLimit(player.UserId, "cars") -- { allowed, current, limit }
```

Config pendiente por deploy:
1. `ApiKey` real (sk_live_ con readwrite en AGA_*).
2. `Places.activation.PlaceId` (el de "Activación AGA").
3. Confirmar `Places.street.PlaceId`.

---

## 4) Web (plantilla en `web/`)

- `index.html` — Landing AGA (paleta rojo/naranja/grafito) con **selector de las 2
  experiencias** → deep link al place elegido con `launchData={qrCode, companyId:"aga", experience}`.
- `reporte.html` — Dropdown **Logrus (LGR) / AGA** + dentro de AGA, **filtro por
  experiencia** (Todas / Carrera / Activación) con tabla comparativa `byExperience`.
- Copiar a una App de Praxsuite (`aga-*.praxsuite.app`) y publicar páginas `/`, `/qr`, `/reporte`
  (mismo patrón de despliegue que Electrolit).

## 5) Checklist de replicación

- [ ] API key AGA readwrite otorgada a las 4 tablas AGA_* (hecho para v1/v2/MCP)
- [ ] PlaceIds reales en `AGACentralService.lua` y `web/index.html`
- [ ] Apps web AGA publicadas (Landing + Reporte)
- [ ] Lote de códigos AGA minteado (`AGA-2026-…`) y QR PNG generados
- [ ] `AGACentralService` incluido en ServerScriptService de ambos juegos
- [ ] Remote `ClaimQRRemote` de cada juego apuntando a `AGACentral:ClaimCode`
