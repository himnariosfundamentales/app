'use strict';

// Desde Flutter 3.x el flutter_service_worker.js generado ya no guarda nada
// en caché (se da de baja solo), por eso la app registra este en su lugar
// desde web/flutter_bootstrap.js.
const CACHE = 'himnario-v1';

const ARCHIVOS_BASE = [
  './',
  'flutter_bootstrap.js',
  'manifest.json',
  'favicon.png',
  'icons/Icon-192.png',
  'icons/Icon-512.png',
];

// Recursos externos con URL versionada: si ya están en caché no cambian.
const HOSTS_EXTERNOS = ['fonts.gstatic.com', 'www.gstatic.com'];

// Cada worker nuevo baja la app completa antes de tomar el control: quien venga
// del worker de antes (red primero) podría tener guardada una versión vieja sin
// "Actualizar" que use actualizarApp, y appGuardada ya no la reemplazaría.
self.addEventListener('install', (event) => {
  self.skipWaiting();
  event.waitUntil(actualizarApp());
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      const nombres = await caches.keys();
      await Promise.all(
        nombres.filter((nombre) => nombre !== CACHE).map((nombre) => caches.delete(nombre))
      );
      await borrarPdfViejos();
      await self.clients.claim();
    })()
  );
});

// Los himnos pasaron de PDF a WebP: se borran solo los PDF (~400 MB) y no la
// caché entera, porque ahí también está la app que se necesita sin conexión.
async function borrarPdfViejos() {
  const cache = await caches.open(CACHE);
  for (const request of await cache.keys()) {
    if (new URL(request.url).pathname.endsWith('.pdf')) await cache.delete(request);
  }
}

self.addEventListener('fetch', (event) => {
  const request = event.request;
  // 'no-store' es versiones.json: siempre de la red, nunca una copia vieja.
  if (request.method !== 'GET' || request.cache === 'no-store') return;

  const url = new URL(request.url);
  if (url.origin === self.location.origin) {
    if (url.pathname.endsWith('/portada.webp')) {
      // Las portadas pueden cambiar sin que cambie versiones.json: se muestra
      // la guardada y se revisa en segundo plano para la próxima vez.
      event.respondWith(guardadaYRevisar(event));
    } else if (url.pathname.includes('/assets/himnarios/')) {
      // Las hojas no cambian salvo que la app pida la versión nueva
      // ('reload'), cuando versiones.json indica que cambió.
      event.respondWith(
        request.cache === 'reload' ? descargarYGuardar(request) : cachePrimero(request)
      );
    } else {
      event.respondWith(appGuardada(request));
    }
  } else if (HOSTS_EXTERNOS.includes(url.hostname)) {
    event.respondWith(cachePrimero(request));
  }
});

function descargarYGuardar(request) {
  return fetch(request).then(async (respuesta) => {
    await guardarSiCambio(request, respuesta.clone());
    return respuesta;
  });
}

async function guardarSiCambio(request, respuesta) {
  if (!respuesta.ok) return;
  try {
    const cache = await caches.open(CACHE);
    const etag = respuesta.headers.get('etag');
    const guardada = etag ? await cache.match(request) : undefined;
    // Si el servidor dice que no cambió no se reescribe (las portadas se
    // revisan cada vez que se muestran).
    if (guardada && guardada.headers.get('etag') === etag) {
      await respuesta.body?.cancel();
      return;
    }
    await cache.put(request, respuesta);
  } catch (e) {
    console.warn('No se pudo guardar en caché', request.url, e);
  }
}

async function cachePrimero(request) {
  const guardada = await caches.match(request);
  return guardada ?? descargarYGuardar(request);
}

// App (index.html, main.dart.js, canvaskit...): la copia guardada, sin esperar
// a la red. Antes se pedía todo a la red en cada arranque (hasta 4 s de espera)
// y GitHub Pages da un ETag distinto según el servidor que conteste, así que
// main.dart.js se volvía a bajar casi siempre: la app tardaba 3-4 s en abrir.
// La versión nueva llega solo con "Actualizar" (ver 'actualizar' abajo), que la
// baja completa de una vez para no mezclar archivos de dos versiones.
async function appGuardada(request) {
  const guardada =
    (await caches.match(request)) ??
    (request.mode === 'navigate' ? await caches.match('./') : undefined);
  if (guardada) return sinReusoEnMemoria(guardada);
  const respuesta = await fetch(request, { cache: 'no-cache' });
  await guardarSiCambio(request, respuesta.clone());
  return sinReusoEnMemoria(respuesta);
}

async function guardadaYRevisar(event) {
  const request = event.request;
  const red = fetch(request, { cache: 'no-cache' }).then(async (respuesta) => {
    await guardarSiCambio(request, respuesta.clone());
    return respuesta;
  });
  const guardada = await caches.match(request);
  if (guardada) {
    event.waitUntil(red.catch(() => {}));
    return guardada;
  }
  return red;
}

// La app pide la versión nueva ("Actualizar", cuando despliegue.txt dice que
// se publicó otra): se bajan de nuevo todos los archivos de la app guardados
// (no las hojas de los himnarios) y solo si llegaron todos se reemplazan, para
// no quedar con una mezcla. Uno que ya no existe (404) se borra, salvo los de
// ARCHIVOS_BASE. Responde 'ok' o el error por el puerto del mensaje.
self.addEventListener('message', (event) => {
  if (event.data?.tipo !== 'actualizar') return;
  const puerto = event.ports[0];
  event.waitUntil(
    actualizarApp().then(
      () => puerto?.postMessage('ok'),
      (e) => puerto?.postMessage(String(e))
    )
  );
});

async function actualizarApp() {
  const cache = await caches.open(CACHE);
  const base = new Set(ARCHIVOS_BASE.map((archivo) => new URL(archivo, self.registration.scope).href));
  const urls = new Set(base);
  for (const request of await cache.keys()) {
    const url = new URL(request.url);
    if (url.origin === self.location.origin && !url.pathname.includes('/assets/himnarios/')) {
      urls.add(request.url);
    }
  }
  const nuevas = await Promise.all(
    [...urls].map(async (url) => {
      const respuesta = await fetch(url, { cache: 'reload' });
      if (respuesta.status === 404 && !base.has(url)) return [url, null];
      if (!respuesta.ok) throw new Error(`${respuesta.status} ${url}`);
      return [url, respuesta];
    })
  );
  await Promise.all(
    nuevas.map(([url, respuesta]) => (respuesta ? cache.put(url, respuesta) : cache.delete(url)))
  );
}

// Chrome guarda en memoria los scripts ya cargados (main.dart.js, canvaskit.js)
// y al recargar los reutiliza sin pasar por aquí mientras el Cache-Control de
// GitHub Pages (10 minutos) diga que siguen frescos: "Actualizar" recargaba la
// versión vieja. Con no-cache tiene que volver a pedírselos a este worker.
function sinReusoEnMemoria(respuesta) {
  if (!respuesta.ok) return respuesta;
  const encabezados = new Headers(respuesta.headers);
  encabezados.set('Cache-Control', 'no-cache');
  return new Response(respuesta.body, {
    status: respuesta.status,
    statusText: respuesta.statusText,
    headers: encabezados,
  });
}
