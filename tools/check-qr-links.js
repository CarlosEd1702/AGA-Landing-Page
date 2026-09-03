/**
 * ============================================================================
 *  check-qr-links.js — Verificación de QR / deep links AGA (Demo)
 * ============================================================================
 *  Valida que los QR y botones de web/qr.html e index.html apunten a los
 *  PlaceIds REALES de Roblox con launchData=AGA_BOTTLE_PROMO y que esas URLs
 *  respondan sin 404 (los PlaceIds publicados devuelven 200 en roblox.com).
 *
 *  Uso:  node tools/check-qr-links.js
 *
 *  Esto cubre el "click test" automatizable sin navegador (TestSprite puede
 *  correrlo contra la URL pública; el chequeo de HTTP valida el destino final).
 * ============================================================================
 */
const fs = require("fs");
const path = require("path");

const EXPECTED = {
  street: {
    placeId: "123585082660675",
    name: "Carrera para Impresionar",
    url: "https://www.roblox.com/games/123585082660675/?launchData=AGA_BOTTLE_PROMO",
  },
  activation: {
    placeId: "99086248105983",
    name: "Activación AGA",
    url: "https://www.roblox.com/games/99086248105983/?launchData=AGA_BOTTLE_PROMO",
  },
};
const CAMPAIGN = "AGA_BOTTLE_PROMO";

function read(name) {
  return fs.readFileSync(path.join(__dirname, "..", "web", name), "utf8");
}

let failures = 0;
const fail = (msg) => { failures++; console.log("  ✗ " + msg); };
const ok = (msg) => console.log("  ✓ " + msg);

async function check() {
  console.log("=== 1) URLs destino esperadas en qr.html ===");
  const qr = read("qr.html");

  for (const exp of ["street", "activation"]) {
    const expected = EXPECTED[exp];
    // 1a) El QR (imagen) debe codificar la URL directa
    const qrEncoded = encodeURIComponent(expected.url);
    // 1a) La URL se arma en runtime con qrDestination(exp) + api.qrserver.com:
    //     se valida que exista la función generadora y la plantilla de URL directa.
    const hasFn = /function qrDestination\(exp\)/.test(qr);
    const hasTemplate = qr.includes('"https://www.roblox.com/games/" + place.id + "/?launchData=" + CAMPAIGN');
    if (hasFn && hasTemplate) {
      ok(exp + ": qrDestination genera la URL directa (plantilla verificada)");
    } else {
      fail(exp + ": no se encontró qrDestination o la plantilla de URL directa");
    }
    // 1b) El PlaceId del lobby debe aparecer con su launchData
    if (qr.includes(expected.placeId) && qr.includes(CAMPAIGN)) {
      ok(exp + ": PlaceId " + expected.placeId + " + launchData " + CAMPAIGN + " presentes");
    } else {
      fail(exp + ": falta PlaceId " + expected.placeId + " o " + CAMPAIGN);
    }
  }

  console.log("=== 2) Sin subdominio intermedio (aga.praxsuite.app) ===");
  const all = qr + "\n" + read("index.html");
  if (all.includes("aga.praxsuite.app")) {
    fail("Todavía existe una referencia a aga.praxsuite.app");
  } else {
    ok("No hay referencias a aga.praxsuite.app en qr.html ni index.html");
  }

  console.log("=== 3) HTTP status de los destinos finales (esperado 200, no 404) ===");
  for (const exp of ["street", "activation"]) {
    const expected = EXPECTED[exp];
    try {
      // Roblox responde a GET de juegos existentes; 200 = place publicado.
      const res = await fetch(expected.url, { method: "GET", redirect: "follow" });
      const status = res.status;
      if (status === 200) {
        ok(exp + " (" + expected.name + ") → HTTP " + status);
      } else {
        fail(exp + " (" + expected.name + ") → HTTP " + status + " — revisar si el PlaceId está publicado");
      }
    } catch (e) {
      fail(exp + ": error de red/HTTP → " + e.message);
    }
  }

  console.log("");
  if (failures === 0) {
    console.log("✅ TODAS LAS VERIFICACIONES PASARON — los QR dirigen a los lobbies correctos sin 404.");
  } else {
    console.log("❌ " + failures + " verificación(es) fallaron — revisar arriba.");
    process.exitCode = 1;
  }
}

check();
