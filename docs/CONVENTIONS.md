# Convenciones de Arquitectura — AGA Landing Page

> Este archivo existe para que cualquier agente (DeepSeek Harness, Claude Code, u otro) lo lea
> **antes** de tocar código en este repo. Si una regla de aquí y el código no coinciden, gana
> este archivo — y hay que corregir el código, no la regla.

> ⚠️ **Estado actual vs objetivo (léelo antes de tocar código).**
> Hoy el repo **es HTML plano legacy** (`web/index.html`, `web/qr.html`, `web/reporte.html`,
> `web/config.js`) SIN Vite ni React. La estructura `src/lib/`, `components/`, `pages/` y
> `vite.config.ts` que describe este doc es el **estado OBJETIVO**, todavía NO implementado.
> Regla práctica: **no migres a Vite+React de golpe.** El bug histórico (SCAN_URL a Electrolit)
> fue por copiar/pegar, no por la falta de React. El paso 1 y de mayor valor es extraer `lib/`
> compartido manteniendo HTML + template literals; Vite+React es un paso posterior opcional.

## 1. Fuente única de verdad

Ningún dato que aparezca en más de un lugar debe copiarse. Vive en `src/lib/`:

- `places.ts` → IDs de experiencias Roblox, nombres, campaign token (`PLACES`, `CAMPAIGN`).
- `nav.ts` → tabla de rutas y función `go()`.
- `deepLink.ts` → lógica de apertura app/web (`DeepLinkHandler`).
- `praxsuite.ts` → URLs de endpoints (scan register, dashboard).
- `config.ts` → wrapper tipado sobre `window.AGA` (feature flags).

**Regla dura:** si estás por copiar/pegar un bloque de JS/TS de un archivo a otro, para. Ese
bloque va a `lib/`, se importa desde ahí en los dos lados.

## 2. Secretos y credenciales

- Ningún token, API key o Bearer va escrito literal en un archivo que se commitea (`.ts`,
  `.tsx`, `.yml`, `.json`, `.html`).
- Van en variables de entorno (`.env`, excluido en `.gitignore`) o en el secrets store
  correspondiente (Praxsuite Secrets Store, GitHub Actions secrets, etc.).
- **Excepción explícita:** los endpoints de Praxsuite marcados "Sync, sin auth" no son un
  secreto (son URLs de capability, no credenciales) — pero igual viven en `lib/praxsuite.ts`,
  un solo lugar, nunca repetidos en más de un archivo.
- Antes de cada commit: grep del diff por `sk_live_`, `sk-`, `Bearer `, `API_KEY`, `TOKEN`. Si
  aparece algo, para y muévelo a `.env`.

## 2b. Endpoints de Praxsuite: auth / origin allowlisting

Los endpoints "Sync, sin auth" no guardan credenciales, pero **siguen siendo llamables por
cualquiera** que abra DevTools y haga POST directo — puede inflar `AGA_QR_Scans` con escaneos
falsos o pegarle al dashboard sin pasar por la página. Reglas:

- El endpoint de **escritura** (scan register) DEBE tener **origin allowlisting**
  (`add_origin_to_endpoint` en Praxsuite) restringido a los orígenes reales de la app
  (`https://<app>.praxsuite.app` y `http://localhost:5173` para dev). Sin allowlist de origen,
  no se mergea.
- El endpoint de lectura (dashboard) también debería llevar allowlist de origen, aunque el
  riesgo es menor (solo lectura).
- **No** "arreglar" con una capa PHP/proxy intermedia: solo mueve el problema un nivel. La
  protección real es auth o allowlist en el propio endpoint de Praxsuite.
- Si un día el endpoint necesita auth real, migrar a endpoint firmado o a llamadas
  server-side con API key (nunca exponer `sk_` al navegador).

## 3. Feature flags: los dos lados deben coincidir SIEMPRE

`qrRedemptionEnabled` vive en dos sitios que **no comparten runtime**:

- `public/config.js` (web)
- `AGAModuleConfig.lua` (Roblox, replicado en cada lobby)

- Nunca cambies uno sin el otro.
- Usa `tools/set-mode.ps1|sh` — no edites `config.js` a mano.
- Antes de dar por cerrado un cambio de modo: corre el check de consistencia (sección 5) y
  confirma visualmente en Studio que ambos lobbies quedaron en el mismo valor.

## 4. Estructura del proyecto (multi-page, no SPA)

```
web/
  public/
    config.js          ← NO se bundlea; se edita y despliega solo
                          (así el toggle demo⇄entrega no exige rebuild)
  src/
    lib/                ← única fuente de verdad (sección 1)
    components/
      Nav.tsx
      Layout.tsx
    pages/
      Home.tsx
      Qr.tsx
      Reporte.tsx
    entries/
      main-home.tsx
      main-qr.tsx
      main-reporte.tsx
  index.html   qr.html   reporte.html
  vite.config.ts        ← build multi-page, un entry por .html
```

- Se mantiene multi-page (no `react-router`) porque el deploy es HTML estático servido por
  Praxsuite — no hay rewrites de servidor garantizados para rutas de SPA.
- Un componente usado por 2+ páginas SIEMPRE va a `components/`, nunca duplicado dentro de
  `pages/`.

## 4b. XSS y renderizado de datos dinámicos

- Todo valor que venga de Praxsuite o de input de usuario y se inyecte al DOM debe **escaparse**.
  - Con Vite+React: el escape por defecto de JSX ya lo cubre (no usar `dangerouslySetInnerHTML`
    salvo excepción justificada y revisada).
  - Con HTML plano + template literals (estado actual): usar un helper `esc()` compartido en
    `lib/` para TODO valor interpolado (nombres de experiencia, códigos, ArcadeName futuro).
- `innerHTML` + concatenación de strings sin escapar está **prohibido** para datos dinámicos.
- Hoy el riesgo es bajo (los nombres vienen de config), pero `ArcadeName` (input de usuario
  sanitizado en Roblox, no pensado para HTML) es el caso que lo volvería XSS real si se
  muestra sin escapar.

## 4c. Contenido no contratado (módulo Add-On)

- En modo Entrega, ocultar la vista con `display:none` NO evita que el HTML/JS del Add-On viaje
  al navegador de AGA. Es un detalle contractual más que técnico.
- Si importa que AGA no reciba ni el markup de un módulo que no pagó, el build de Entrega debe
  **generar el HTML sin** la vistaDemo/QR (no solo ocultarla).
- Lo contractual de fondo se garantiza en el **servidor de Roblox** (flag `AGAModuleConfig`) —
  el ocultado en web es presentación, no control de acceso.

## 5. Checklist antes de mergear / publicar

- [ ] ¿Algún valor (URL, ID, texto) aparece copiado en 2+ archivos? → moverlo a `lib/`.
- [ ] ¿Algún secreto quedó literal en el diff? → grep de la sección 2.
- [ ] ¿Cambié `qrRedemptionEnabled`? → ¿cambié también `AGAModuleConfig.lua` en **ambos**
      lobbies?
- [ ] ¿Añadí o toqué un endpoint de Praxsuite? → ¿tiene **origin allowlisting** (sección 2b)?
- [ ] ¿Inyecté datos dinámicos al DOM? → ¿van escapados con `esc()` / JSX (sección 4b)?
- [ ] ¿Sigo en HTML legacy o ya migré a Vite? → confirmar cuál es el estado real (sección ⚠️).
- [ ] Corrida de TestSprite sobre las 3 páginas/endpoints antes de republicar producción.
- [ ] ¿Agregué un tenant nuevo (ej. Electrolit)? → ¿el selector de empresa lee de una lista en
      `lib/`, no hardcodeada en el JSX?

## 6. Cuándo consultar Context7

Antes de generar código nuevo con una librería (React, Vite, Chart.js, etc.), consulta Context7
para la versión/API vigente — no asumas del training data del modelo.

## Por qué existe este archivo

Nació después del bug de `SCAN_URL` apuntando al endpoint de Electrolit en vez de AGA
(documentado en `Feature Flags — Demo QR ⇄ Entrega`, corregido en el commit correspondiente),
causado por triplicar el mismo bloque de código en `index.html`, `qr.html` y `reporte.html` sin
una fuente única. Estas reglas existen para que ese tipo de error deje de ser posible por
diseño, no por memoria humana.
