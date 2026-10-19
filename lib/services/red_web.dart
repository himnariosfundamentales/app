import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;

import 'package:web/web.dart' as web;

/// Acceso directo a la red y a la caché del navegador. La app solo se publica
/// como PWA, así que puede usar las APIs web sin alternativa para móvil.
class RedWeb {
  // Tiene que coincidir con CACHE en web/sw.js.
  static const String _cache = 'himnario-v1';

  /// La misma URL que usa `rootBundle.load` para ese asset.
  static String urlDeAsset(String ruta) =>
      ui_web.assetManager.getAssetUrl(ruta);

  /// URL de un archivo publicado junto a index.html (respeta el base-href).
  static String urlDelSitio(String archivo) =>
      Uri.parse(web.document.baseURI).resolve(archivo).toString();

  static void recargarPagina() => web.window.location.reload();

  /// Lee un archivo de texto sin pasar por ninguna caché. Devuelve null si no
  /// hay internet o el archivo no existe.
  static Future<String?> leerSinCache(String url) async {
    try {
      final web.Response respuesta = await web.window
          .fetch(url.toJS, web.RequestInit(cache: 'no-store'))
          .toDart;
      if (!respuesta.ok) return null;
      return (await respuesta.text().toDart).toDart;
    } catch (_) {
      return null;
    }
  }

  /// Baja la versión más nueva del archivo desde el servidor y la deja
  /// guardada en el dispositivo. Con [huella] solo cuenta si lo que llegó es
  /// esa versión: justo después de publicar, el servidor puede seguir
  /// entregando la anterior unos minutos.
  static Future<bool> descargarVersionNueva(
    String url, {
    String? huella,
  }) async {
    try {
      final web.Response respuesta = await web.window
          .fetch(url.toJS, web.RequestInit(cache: 'reload'))
          .toDart;
      if (!respuesta.ok) return false;
      final Uint8List datos = (await respuesta.arrayBuffer().toDart).toDart
          .asUint8List();
      final String recibida = await huellaDe(datos);
      if (huella != null && recibida != huella) return false;
      // Normalmente la guarda el service worker al pasar la descarga. Si no
      // controla la página (en la primera visita puede tardar en tomar el
      // control) o no pudo guardarla, se guarda desde aquí.
      if (await huellaGuardada(url) != recibida) {
        await guardar(
          url,
          datos,
          respuesta.headers.get('Content-Type') ?? 'image/webp',
        );
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Huella de la copia guardada en el dispositivo. Null si no está.
  static Future<String?> huellaGuardada(String url) async {
    final Uint8List? datos = await leerGuardado(url);
    return datos == null ? null : huellaDe(datos);
  }

  /// Huella calculada igual que en `tool/generar_versiones.py` (SHA-256, 12
  /// caracteres).
  static Future<String> huellaDe(Uint8List datos) async {
    final JSAny? resumen = await web.window.crypto.subtle
        .digest('SHA-256'.toJS, datos.toJS)
        .toDart;
    return (resumen as JSArrayBuffer).toDart
        .asUint8List()
        .take(6)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  /// La copia guardada en el dispositivo. Null si no está.
  static Future<Uint8List?> leerGuardado(String url) async {
    try {
      final web.Response? respuesta = await web.window.caches
          .match(url.toJS)
          .toDart;
      if (respuesta == null) return null;
      return (await respuesta.arrayBuffer().toDart).toDart.asUint8List();
    } catch (_) {
      return null;
    }
  }

  /// Guarda [datos] como si se hubieran descargado de [url]: el service
  /// worker los entrega desde ahí sin pedirlos al servidor.
  static Future<void> guardar(String url, Uint8List datos, String tipo) async {
    final web.Cache cache = await web.window.caches.open(_cache).toDart;
    final web.Headers encabezados = web.Headers()
      ..set('Content-Type', tipo)
      ..set('Content-Length', '${datos.length}');
    await cache
        .put(
          url.toJS,
          web.Response(datos.toJS, web.ResponseInit(headers: encabezados)),
        )
        .toDart;
  }

  /// Datos en la memoria del navegador (puede usar el disco si son grandes),
  /// para armar archivos grandes sin copiarlos en la memoria de la app.
  static web.Blob aBlob(Uint8List datos) => web.Blob(<JSAny>[datos.toJS].toJS);

  /// Descarga un archivo armado con [partes]: en Android va a Descargas, en
  /// iPad pregunta dónde guardarlo.
  static void descargarArchivo(
    List<web.Blob> partes,
    String nombre,
    String tipo,
  ) {
    final web.Blob archivo = web.Blob(
      partes.toJS,
      web.BlobPropertyBag(type: tipo),
    );
    final String url = web.URL.createObjectURL(archivo);
    (web.HTMLAnchorElement()
          ..href = url
          ..download = nombre)
        .click();
    // Se libera después: si se libera enseguida, algunos navegadores cancelan
    // la descarga antes de empezar.
    Future<void>.delayed(const Duration(minutes: 1), () {
      web.URL.revokeObjectURL(url);
    });
  }

  /// Abre el selector de archivos del dispositivo. Tiene que llamarse
  /// directamente desde un toque (sin esperas antes), o el navegador lo
  /// bloquea. Null si el usuario no eligió nada.
  static Future<web.File?> elegirArchivo(String aceptar) {
    final Completer<web.File?> elegido = Completer();
    final web.HTMLInputElement selector = web.HTMLInputElement()
      ..type = 'file'
      ..accept = aceptar;
    selector.style.display = 'none';
    void terminar(web.File? archivo) {
      if (!elegido.isCompleted) elegido.complete(archivo);
      selector.remove();
    }

    selector.addEventListener(
      'change',
      ((web.Event _) {
        final web.FileList? archivos = selector.files;
        terminar(
          archivos != null && archivos.length > 0 ? archivos.item(0) : null,
        );
      }).toJS,
    );
    selector.addEventListener('cancel', ((web.Event _) => terminar(null)).toJS);
    web.document.body!.append(selector);
    selector.click();
    return elegido.future;
  }

  /// Bytes de [inicio] a [fin] del archivo, sin leer el resto.
  static Future<Uint8List> leerTrozo(
    web.Blob archivo,
    int inicio,
    int fin,
  ) async => (await archivo.slice(inicio, fin).arrayBuffer().toDart).toDart
      .asUint8List();

  /// Descomprime un trozo comprimido con deflate (el método normal de ZIP).
  static Future<Uint8List> descomprimir(web.Blob trozo) async {
    final web.DecompressionStream descompresor = web.DecompressionStream(
      'deflate-raw',
    );
    final web.ReadableStream salida = trozo.stream().pipeThrough(
      web.ReadableWritablePair(
        readable: descompresor.readable,
        writable: descompresor.writable,
      ),
    );
    return (await web.Response(
      salida,
    ).arrayBuffer().toDart).toDart.asUint8List();
  }

  /// Pide que el navegador no borre lo guardado aunque el dispositivo se
  /// quede sin espacio. Sin esto los datos son "de mejor esfuerzo". Devuelve
  /// si lo concedió (Chrome decide solo; Firefox pregunta al usuario).
  static Future<bool> pedirAlmacenamientoPersistente() async {
    try {
      return (await web.window.navigator.storage.persist().toDart).toDart;
    } catch (_) {
      return false;
    }
  }

  /// Cuáles de [urls] están guardadas en el dispositivo, con una sola consulta
  /// a la caché: preguntar por cientos de hojas de a una era lento.
  static Future<List<bool>> estanGuardadas(List<String> urls) async {
    Set<String> guardadas = {};
    try {
      final web.Cache cache = await web.window.caches.open(_cache).toDart;
      guardadas = {
        for (final web.Request request in (await cache.keys().toDart).toDart)
          request.url,
      };
    } catch (_) {}
    // La caché las devuelve completas; las de los assets son relativas.
    return [
      for (final String url in urls) guardadas.contains(urlDelSitio(url)),
    ];
  }

  static Future<void> borrarGuardados(Iterable<String> urls) async {
    try {
      final web.Cache cache = await web.window.caches.open(_cache).toDart;
      await Future.wait(urls.map((url) => cache.delete(url.toJS).toDart));
    } catch (_) {}
  }

  // Los mismos que guarda web/sw.js además de los del sitio (las fuentes).
  static const List<String> _hostsExternos = [
    'fonts.gstatic.com',
    'www.gstatic.com',
  ];

  /// Guarda los archivos de la app que ya se cargaron sin pasar por el
  /// service worker (main.dart.js, canvaskit, fuentes...). En la primera
  /// visita la app puede arrancar antes de que el service worker controle la
  /// página, y entonces nada de eso queda guardado: la app no abriría sin
  /// internet aunque los himnarios estén descargados.
  static Future<void> guardarArchivosDeLaApp() async {
    try {
      final web.Cache cache = await web.window.caches.open(_cache).toDart;
      final String origen = web.window.location.origin;
      for (final web.PerformanceEntry entrada
          in web.window.performance.getEntriesByType('resource').toDart) {
        final String url = entrada.name;
        final Uri uri = Uri.parse(url);
        if ((entrada as web.PerformanceResourceTiming).workerStart > 0 ||
            !(url.startsWith(origen) || _hostsExternos.contains(uri.host)) ||
            uri.path.contains('/assets/himnarios/') ||
            uri.path.endsWith('/sw.js') ||
            uri.path.endsWith('/despliegue.txt')) {
          continue;
        }
        try {
          if (await cache.match(url.toJS).toDart == null) {
            await cache.add(url.toJS).toDart;
          }
        } catch (_) {}
      }
    } catch (_) {}
  }
}
