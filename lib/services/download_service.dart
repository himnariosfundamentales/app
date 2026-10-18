import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/himnario.dart';
import '../models/himno.dart';
import 'red_web.dart';

/// Hojas de un himnario: la ruta de cada página de cada himno, y todas las
/// hojas sin repetir (una hoja puede tener el final de un himno y el inicio
/// del siguiente).
class _Hojas {
  final Map<int, List<String>> porHimno;
  final List<String> todas;

  const _Hojas(this.porHimno, this.todas);
}

/// Cada hoja es una imagen WebP dentro de la app:
/// `assets/himnarios/<himnario>/<numero>-<pagina>.webp`, o
/// `2-2_3-1.webp` si trae la página 2 del himno 2 y la 1 del himno 3. En web,
/// `rootBundle.load` hace una petición que intercepta `web/sw.js` y guarda en
/// la caché del navegador, así que "descargar" es pedir todas las hojas una
/// vez para que queden disponibles sin conexión.
class DownloadService {
  // Con 8 a la vez la descarga fue ~55% más rápida que con 4 (medido contra
  // GitHub Pages): el límite era la espera de cada petición, no la conexión.
  static const int descargasSimultaneas = 8;
  static final RegExp _parte = RegExp(r'^(\d+)-(\d+)$');

  static final Map<String, Future<_Hojas>> _hojas = {};

  static String _keyDescargaCompleta(Himnario himnario) =>
      'descarga_${himnario.id}';

  /// Ruta del asset de una hoja: "34-1" es el himno 34, página 1.
  static String rutaHoja(Himnario himnario, String clave) =>
      '${himnario.carpeta}$clave.webp';

  /// Clave de una hoja ("34-1" o "2-2_3-1") a partir de la ruta de su asset.
  static String claveDe(Himnario himnario, String ruta) =>
      ruta.substring(himnario.carpeta.length, ruta.length - '.webp'.length);

  /// Manifiesto del himnario, generado por `tool/generar_versiones.py`.
  static String rutaManifiesto(Himnario himnario) =>
      '${himnario.carpeta}versiones.json';

  static Future<bool> estaDescargado(Himnario himnario) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyDescargaCompleta(himnario)) ?? false;
  }

  static Future<void> marcarDescargaCompleta(Himnario himnario) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyDescargaCompleta(himnario), true);
  }

  /// Baja todas las hojas del himnario. Devuelve cuántas no se pudieron
  /// descargar (0 = todo bien). Con [huellasPublicadas] ("34-1" → huella),
  /// las hojas que ya están guardadas e iguales a las publicadas no se
  /// vuelven a bajar.
  static Future<int> descargar(
    Himnario himnario, {
    required void Function(int completadas, int total) onProgreso,
    Map<String, String>? huellasPublicadas,
  }) async {
    final List<String> rutas;
    try {
      rutas = await todasLasRutas(himnario);
    } catch (e) {
      debugPrint('No se pudo leer la lista de hojas de ${himnario.id}: $e');
      return 1;
    }
    int completadas = 0;
    int fallidas = 0;

    for (int i = 0; i < rutas.length; i += descargasSimultaneas) {
      await Future.wait(
        rutas.skip(i).take(descargasSimultaneas).map((ruta) async {
          final String url = RedWeb.urlDeAsset(ruta);
          final String? publicada = huellasPublicadas?[claveDe(himnario, ruta)];
          final bool alDia =
              publicada != null &&
              await RedWeb.huellaGuardada(url) == publicada;
          if (!alDia && !await RedWeb.descargarVersionNueva(url)) {
            fallidas++;
            debugPrint('No se pudo descargar $ruta');
          }
          completadas++;
          onProgreso(completadas, rutas.length);
        }),
      );
    }

    if (fallidas > 0) return fallidas;
    // Solo cuenta como descargado si todas las hojas quedaron guardadas en el
    // dispositivo (sin HTTPS, por ejemplo, el navegador no deja guardar nada).
    final List<bool> guardadas = await Future.wait(
      rutas.map((ruta) => RedWeb.estaGuardado(RedWeb.urlDeAsset(ruta))),
    );
    final int sinGuardar = guardadas.where((guardada) => !guardada).length;
    if (sinGuardar == 0) await marcarDescargaCompleta(himnario);
    return sinGuardar;
  }

  /// Rutas de las páginas del himno, en orden.
  static Future<List<String>> paginasDe(Himnario himnario, Himno himno) async =>
      (await _leer(himnario)).porHimno[himno.numero] ?? const [];

  /// Rutas de todas las hojas del himnario, cada una una sola vez.
  static Future<List<String>> todasLasRutas(Himnario himnario) async =>
      (await _leer(himnario)).todas;

  static Future<_Hojas> _leer(Himnario himnario) async {
    final Future<_Hojas> lectura = _hojas[himnario.id] ??= _leerManifiesto(
      himnario,
    );
    try {
      return await lectura;
    } catch (_) {
      // Sin esto, un fallo (por ejemplo, sin internet la primera vez) quedaría
      // guardado y no se volvería a intentar.
      if (identical(_hojas[himnario.id], lectura)) _hojas.remove(himnario.id);
      rethrow;
    }
  }

  static Future<_Hojas> _leerManifiesto(Himnario himnario) async {
    final AssetManifest manifiesto = await AssetManifest.loadFromAssetBundle(
      rootBundle,
    );
    final Map<int, Map<int, String>> encontradas = {};
    final List<(int, int, String)> hojas = [];
    for (final String ruta in manifiesto.listAssets()) {
      if (!ruta.startsWith(himnario.carpeta) || !ruta.endsWith('.webp')) {
        continue;
      }
      final List<RegExpMatch?> partes = [
        for (final String parte in claveDe(himnario, ruta).split('_'))
          _parte.firstMatch(parte),
      ];
      if (partes.any((parte) => parte == null)) continue; // la portada
      for (final RegExpMatch? parte in partes) {
        encontradas.putIfAbsent(
          int.parse(parte![1]!),
          () => {},
        )[int.parse(parte[2]!)] = ruta;
      }
      hojas.add((
        int.parse(partes.first![1]!),
        int.parse(partes.first![2]!),
        ruta,
      ));
    }
    hojas.sort(
      (a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2),
    );
    return _Hojas(
      encontradas.map((numero, paginas) {
        final List<int> orden = paginas.keys.toList()..sort();
        return MapEntry(numero, [for (final p in orden) paginas[p]!]);
      }),
      [for (final (_, _, String ruta) in hojas) ruta],
    );
  }

  static Future<Uint8List> obtenerPagina(String ruta) async {
    final ByteData datos = await rootBundle.load(ruta);
    return datos.buffer.asUint8List(datos.offsetInBytes, datos.lengthInBytes);
  }
}
