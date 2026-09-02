/**
 * ============================================================================
 *  DeepLinkHandler — Redirección inteligente a Roblox (iOS / Android / Desktop)
 * ============================================================================
 *  Electrolit Aero Surge · Multi-tenant QR
 *
 *  PROBLEMA QUE RESUELVE:
 *  - En iOS/Android, abrir `roblox://...` con location.href directo no permite
 *    saber si la app se abrió o no; el navegador se queda "colgado" y el
 *    fallback nunca se ejecuta de forma fiable.
 *  - Los pop-up blockers bloquean window.open() si no se llama dentro del
 *    gesto de usuario (click).
 *
 *  SOLUCIÓN:
 *  1. El intento del URL scheme ocurre SIEMPRE dentro del click (gesto de
 *     usuario) para que el navegador no lo bloquee.
 *  2. Se arma un setTimeout de 2.5s como fallback; si `document.hidden`
 *     cambia a true (la app Roblox tomó el foco) el timer se CANCELA y no
 *     redirigimos a la web.
 *  3. Desktop: abre directo la URL web (sin scheme, no hay app).
 *  4. El botón "Abrir navegador web" usa window.open(url, '_blank') llamado
 *     dentro del handler de click → sin bloqueo de pop-up.
 * ============================================================================
 */
const DeepLinkHandler = (() => {
  "use strict";

  // ---- Config por defecto (sobreescribible con DeepLinkHandler.config) ----
  const DEFAULTS = {
    placeId: "80485338724090",
    timeoutMs: 2500, // fallback si la app no abre en 2.5s
    fallbackUrl: null, // si es null se construye desde placeId
  };

  let cfg = Object.assign({}, DEFAULTS);

  // ---- Utilidades ---------------------------------------------------------
  const isIOS = () =>
    /iPad|iPhone|iPod/.test(navigator.userAgent) ||
    (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1);

  const isAndroid = () => /Android/i.test(navigator.userAgent);

  const isMobile = () => isIOS() || isAndroid();

  /**
   * Codifica launchData como JSON url-encoded.
   * @param {object|string} launchData - objeto {qrCode} o string JSON
   */
  const encodeLaunchData = (launchData) => {
    let json;
    if (typeof launchData === "string") {
      // si ya es JSON válido se usa; si es texto plano se envuelve
      try { JSON.parse(launchData); json = launchData; }
      catch (_) { json = JSON.stringify({ launchData: launchData }); }
    } else {
      json = JSON.stringify(launchData || {});
    }
    return encodeURIComponent(json);
  };

  /**
   * Construye el URL scheme de Roblox:
   *   roblox://navigation/game_details?gameId=PLACE_ID&launchData=ENCODED_JSON
   */
  const buildScheme = (placeId, encodedLaunchData) =>
    "roblox://navigation/game_details?gameId=" +
    encodeURIComponent(String(placeId)) +
    "&launchData=" +
    encodedLaunchData;

  /** URL web de la experiencia (fallback + desktop). */
  const buildWebUrl = (placeId, encodedLaunchData) =>
    "https://www.roblox.com/games/" +
    encodeURIComponent(String(placeId)) +
    (encodedLaunchData ? "?launchData=" + encodedLaunchData : "");

  // ---- Detección de primer plano (para cancelar el fallback) --------------
  let appOpened = false;

  const onVisibility = () => {
    if (document.hidden) {
      appOpened = true; // Roblox tomó el foco → no redirigir
    }
  };

  const onPageHide = () => { appOpened = true; }; // iOS Safari / Android

  /**
   * Intenta abrir Roblox vía URL scheme en móviles con fallback temporal.
   * @returns {boolean} true si es móvil (se intentó el scheme)
   */
  const openInApp = () => {
    if (!isMobile()) return false;

    appOpened = false;
    document.addEventListener("visibilitychange", onVisibility, { once: true });
    window.addEventListener("pagehide", onPageHide, { once: true });

    // 1) Intento del scheme dentro del gesto de usuario (click)
    const scheme = buildScheme(cfg.placeId, encodeLaunchData(cfg.launchData));
    window.location.href = scheme;

    // 2) Fallback: si en timeoutMs la app no tomó el foco → abrir web
    setTimeout(() => {
      document.removeEventListener("visibilitychange", onVisibility);
      window.removeEventListener("pagehide", onPageHide);
      if (!appOpened && !document.hidden) {
        const web = buildWebUrl(cfg.placeId, encodeLaunchData(cfg.launchData));
        window.location.href = web;
      }
    }, cfg.timeoutMs);

    return true;
  };

  /**
   * Abre Roblox según plataforma:
   *  - Móvil  → scheme + fallback (openInApp)
   *  - Desktop → web en pestaña nueva (sin pop-up blocker: dentro del click)
   */
  const openRoblox = (opts) => {
    if (opts) cfg = Object.assign({}, DEFAULTS, opts);
    if (openInApp()) return { method: "scheme", mobile: true };
    const web = buildWebUrl(cfg.placeId, encodeLaunchData(cfg.launchData));
    const w = window.open(web, "_blank");
    if (!w) window.location.href = web; // pop-up bloqueado → navegación directa
    return { method: "web", mobile: false };
  };

  /**
   * Botón "Abrir en navegador web": window.open('_blank') dentro del click
   * (requisito anti pop-up blocker). `noopener` evita que la web nueva
   * controle la página actual.
   */
  const openWebBrowser = (opts) => {
    if (opts) cfg = Object.assign({}, DEFAULTS, opts);
    const web = buildWebUrl(cfg.placeId, encodeLaunchData(cfg.launchData));
    const w = window.open(web, "_blank", "noopener");
    if (!w) window.location.href = web;
    return !!w;
  };

  /** Utilidad para enlazar botones por id. */
  const bind = (btnId, opts) => {
    const btn = document.getElementById(btnId);
    if (!btn) return;
    btn.addEventListener("click", (e) => {
      e.preventDefault();
      openRoblox(opts);
    });
  };

  return {
    isMobile,
    isIOS,
    isAndroid,
    buildScheme,
    buildWebUrl,
    encodeLaunchData,
    openRoblox,
    openWebBrowser,
    bind,
    config: (o) => { if (o) cfg = Object.assign({}, DEFAULTS, o); return cfg; },
  };
})();

/* Exposición global (para HTML plano sin bundler) */
if (typeof window !== "undefined") window.DeepLinkHandler = DeepLinkHandler;
if (typeof module !== "undefined" && module.exports) module.exports = DeepLinkHandler;
