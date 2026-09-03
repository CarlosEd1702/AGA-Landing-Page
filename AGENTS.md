# AGENTS.md — Guía para agentes que trabajan en este repo

> Léelo completo ANTES de tocar código. Este archivo es el punto de entrada obligatorio.

## Reglas no negociables

1. **Lee [`docs/CONVENTIONS.md`](docs/CONVENTIONS.md) primero.** Es la fuente de autoridad de
   arquitectura. Si una regla de ahí y el código no coinciden, gana el convenio: corrige el
   código, no la regla.
2. **No dupliques lógica entre páginas.** Hoy el repo es HTML plano (`web/*.html`) con bloques
   JS copiados. Antes de copiar/pegar un bloque de JS entre `index.html`, `qr.html` y
   `reporte.html`, extraelo a un módulo compartido (`src/lib/` o un `web/js/*.js` en el estado
   actual). El bug histórico de `SCAN_URL`→Electrolit nació exactamente de triplicar código.
3. **Secretos:** nunca commitees `sk_live_`, `sk-`, `Bearer `, API keys ni tokens. Van en
   `.env` o Secrets Store. Antes de commitear, hacé grep del diff.
4. **Feature flags en ambos lados:** `web/config.js` y `AGAModuleConfig.lua` (cada lobby) deben
   cambiar juntos. Usa `tools/set-mode.ps1|sh`, no edites a mano.
5. **Endpoints de Praxsuite:** si tocás un endpoint, verificá **origin allowlisting** (sección
   2b de CONVENTIONS.md). No "arregles" con proxies intermedios.
6. **XSS:** escapa todo dato dinámico (`esc()` en HTML plano; JSX en React). Nada de
   `innerHTML` sin escapar para datos de Praxsuite/usuario.

## Mapa rápido del repo

- `web/` → landing multi-page (HTML plano legacy hoy; objetivo Vite multi-page, ver
  CONVENTIONS.md §4).
- `luau/` → módulos Roblox server/client (AGACentralService, AGAModuleConfig, etc.).
- `tools/` → `set-mode.ps1|sh` (toggle Demo⇄Entrega), `check-qr-links.js` (verificación).
- `docs/` → ARCHITECTURE.md, FEATURE_FLAGS.md, CONVENTIONS.md.
- Obsidian (notas): carpeta `Roblox/🏎️ Carrera para Impresionar/` del vault (bitácoras).

## Antes de publicar

Seguí el checklist de CONVENTIONS.md §5 (consistencia de flags, allowlist de endpoints,
escape de datos, corrida de verificación de links/TestSprite).

Para el contexto completo de negocio y el runbook de la demo, ver `docs/FEATURE_FLAGS.md`.
