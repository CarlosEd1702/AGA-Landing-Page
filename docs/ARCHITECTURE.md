# AGA — Arquitectura centralizada (2 experiencias Roblox)

> companyId: `"aga"` · Workspace Praxsuite: `cc6ac8fa-e31c-421d-99af-15951a0e8a7a`

## 🚦 Módulos comerciales y Feature Flags

El contrato AGA incluye **Dashboard de Métricas** (`reporte.html`). El **canje por
QR** es un **Add-On** que se activa solo en Demo. Ver
[`FEATURE_FLAGS.md`](FEATURE_FLAGS.md) para el detalle completo y el runbook.

| Flag | Web (`web/config.js`) | Roblox (`luau/AGAModuleConfig.lua`) |
|---|---|---|
| Canje QR (Add-On) | `features.qrRedemptionEnabled` | `Modules.qrRedemption.Enabled` |
| Dashboard (entregable) | `features.analyticsDashboardEnabled` | `Modules.analyticsDashboard.Enabled` |

Enforcement server-authoritative: `AGACentralService:ClaimCode` y
`AGAQRRedeemService:claimForPlayer` rechazan con `ModuleDisabled=true` (sin tocar
Praxsuite) cuando el flag Roblox está en `false`.

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

### Atribución QR y sesiones (Demo comercial 2026-09-02)

| Tabla | UUID | Rol |
|---|---|---|
| `AGA_QR_Scans` | `562c913c-21a0-4759-8dfa-4ab8acb42eed` | **Atribución de compra**: 1 fila por QR de botella. Nace "1. Escaneado" (landing, sin UserId) y pasa a "2. Ingresó al Juego" cuando el jugador entra a Roblox con `launchData`. Columnas: Scan ID, Code, Company, Experience, Source (`bottle_qr`), Status, Roblox User Id, Place Id, Scanned At, Entered At. |
| `AGA_Game_Sessions` | `dd29d762-7e41-419b-b394-8259b8225dfc` | **Sesiones de juego** de los 4 places AGA: entrada/salida por jugador para heatmap, duración promedio y picos. Columnas: Session ID, Roblox User Id, Place Id, Experience, Source (`bottle_qr`\|`direct`), Code, Entered At, Exited At, Duration Seconds. |

**Flujo de la demo (sin recompensa por ahora):**
1. QR físico (simula botella) → landing `?code=AGA-…` → POST **AGA QR Scan Register** (`863a5932-b44b-4f27-ab2f-1860e4b3d6ff`) → fila en `AGA_QR_Scans` Status "1. Escaneado".
2. Deep link `launchData={qrCode, companyId:"aga", experience}` → Roblox lobby → servidor llama `AGACentralService:RecordQRAttribution` → la fila pasa a "2. Ingresó al Juego" (UserId + PlaceId + Entered At). UI: *"¡Bienvenido desde la promoción AGA!"*.
3. **NO se otorga recompensa** — `GrantReward()` queda comentado/preparado (Add-On futuro). El claim con recompensa sigue cableado en `AGAQRRedeemService`.
4. Cada place AGA registra entrada/salida en `AGA_Game_Sessions` (`AGAGameSessionsService`).

**Dashboard** (`reporte.html`) → endpoint **AGA Dashboard** (`b8023eb1-f4dd-4581-9598-0149d22fef7f`):
- A. Conversión QR: total escaneos, usuarios únicos convertidos, escaneos/convertidos por día.
- B. Engagement: heatmap día×hora (horas pico), duración promedio por experiencia, flujo por hora, jugadores activos por día.

---

## 2) Endpoints (Sync, sin auth — para la web del QR)

| Endpoint | Método/Body | Función |
|---|---|---|
| **AGA Live Stats** (`42064538-6bc8-4e6f-a386-070d929a9220`) | POST `{companyId:"aga", experience:"all"\|"street"\|"activation"}` | KPIs + serie diaria + **byExperience** (comparativa) + últimos canjes. Rechaza companyId ≠ aga. |
| **AGA Dashboard** (`b8023eb1-f4dd-4581-9598-0149d22fef7f`) | POST `{companyId:"aga"}` | Reporte completo: conversión QR (`AGA_QR_Scans`) + engagement (`AGA_Game_Sessions`: heatmap día×hora, duración por experiencia, flujo por hora, activos por día). |
| **AGA QR Scan Register** (`863a5932-b44b-4f27-ab2f-1860e4b3d6ff`) | POST `{code, companyId, experience, placeId}` | La landing llama al escanear un QR de botella → crea/actualiza fila en `AGA_QR_Scans` Status "1. Escaneado" + Scanned At. |
| AGA QR Mint *(plantilla — clonar de EAS `f43bce3d`)* | POST `{prefix, count, experience}` | Genera lote de códigos en `AGA_Promotions` |

> **Nota anti-carrera entre juegos**: el consumo del código ocurre **en el backend**
> (update `AGA_Promotions` con `Roblox User Id` + Status "3. Item Entregado") — cada
> juego solo consulta `AGACentralService:ClaimCode`, que valida y consume en una
> operación; el segundo juego que consulte el mismo código recibirá "ya reclamado".

---

## 3) Módulos Luau compartidos

`luau/AGACentralService.lua` — ModuleScript autocontenido (HttpService → API REST
de Praxsuite, sin SDK interno). Incluirlo en `ServerScriptService` de **ambos** juegos.
Expone además `RecordQRAttribution(params)` (atribución QR en `AGA_QR_Scans`, demo)
y deja `GrantReward()` preparado/comentado (Add-On futuro).

`luau/AGAGameSessionsService.lua` — registra entrada/salida de cada jugador en
`AGA_Game_Sessions` (PlayerAdded/PlayerRemoving). Incluirlo en los **4 places** AGA
(lobbies + pistas) e iniciar con su `Experience` ("street" | "activation").

`luau/AGAModuleConfig.lua` — feature flags server-side (ver FEATURE_FLAGS.md).

```lua
local AGACentral = require(ServerScriptService.AGACentralService)
AGACentral:Init({ ApiKey = "sk_live_...", Places = { street = { PlaceId = "..." }, activation = { PlaceId = "..." } } })

-- Atribución QR (demo, sin recompensa): registrar que el usuario entró vía QR
local attr = AGACentral:RecordQRAttribution({ code = "AGA-2026-0001", userId = tostring(player.UserId), experience = "street", placeId = tostring(game.PlaceId), source = "bottle_qr" })

-- Claim con recompensa (cableado; desactivado en la demo — GrantReward preparado)
-- local res = AGACentral:ClaimCode({ code = "AGA-2026-0001", userId = tostring(player.UserId), experience = "street", placeId = tostring(game.PlaceId) })

-- Inventario global (ambos juegos ven lo mismo)
local inv = AGACentral:GetInventory(player.UserId)          -- crea fila si no existe
AGACentral:AddCoins(player.UserId, 500)
AGACentral:AddTrophies(player.UserId, 1)
AGACentral:UnlockItem(player.UserId, "cars", "AGA-Turbo-01") -- respeta límite
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
