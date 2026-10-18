import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:web/web.dart' as web;
import '../data/catalogo.dart';
import '../models/himnario.dart';
import 'actualizacion_service.dart';
import 'download_service.dart';
import 'red_web.dart';
import 'terminos_service.dart';
import 'zip_simple.dart';

class ResultadoRestauracion {
  final int restauradas;

  /// Hojas del respaldo que venían dañadas y no se guardaron.
  final int danadas;

  /// Hojas de los himnarios restaurados que siguen sin estar en el
  /// dispositivo.
  final int faltantes;

  const ResultadoRestauracion(this.restauradas, this.danadas, this.faltantes);
}

/// Respaldo de los himnarios descargados en un archivo .zip que queda fuera
/// del navegador (Descargas, o Archivos en iPad): si el navegador borra sus
/// datos, se restaura desde ahí sin internet. Adentro va una carpeta
/// `himnarios/<himnario>/` por himnario, con sus hojas y su versiones.json.
class RespaldoService {
  static const int _enParalelo = 8;

  // "himnarios/gracia/2-2_3-1.webp". Los respaldos de la app anterior traen
  // la carpeta en mayúsculas ("HIMNARIOS/<nombre>/34-1.webp") y son las hojas
  // del himnario principal.
  static final RegExp _hoja = RegExp(
    r'(?:^|/)(himnarios)/([^/]+)/([^/]+)\.webp$',
    caseSensitive: false,
  );

  static String _carpeta(Himnario himnario) => 'himnarios/${himnario.id}/';

  static Himnario? _himnarioDe(String raiz, String carpeta) =>
      raiz == 'HIMNARIOS' ? Catalogo.ministerio : Catalogo.porId(carpeta);

  static String nombreArchivo(DateTime fecha) {
    String dos(int n) => n.toString().padLeft(2, '0');
    return 'himnarios-${fecha.year}-${dos(fecha.month)}-${dos(fecha.day)}.zip';
  }

  /// Himnarios descargados completos en este dispositivo: los que entran al
  /// respaldo.
  static Future<List<Himnario>> himnariosDescargados() async => [
    for (final Himnario himnario in Catalogo.todos)
      if (await DownloadService.estaDescargado(himnario)) himnario,
  ];

  /// Arma el respaldo con las hojas guardadas en el dispositivo (sin usar
  /// internet) y lo descarga. Devuelve cuántas hojas faltaban; si falta
  /// alguna no se crea nada, porque el respaldo quedaría incompleto.
  static Future<int> guardar({
    required void Function(int hechas, int total) onProgreso,
  }) async {
    final List<(Himnario, String)> hojas = [
      for (final Himnario himnario in await himnariosDescargados())
        for (final String ruta in await DownloadService.todasLasRutas(himnario))
          (himnario, ruta),
    ];
    final List<bool> guardadas = await Future.wait(
      hojas.map((hoja) => RedWeb.estaGuardado(RedWeb.urlDeAsset(hoja.$2))),
    );
    final int faltantes = guardadas.where((guardada) => !guardada).length;
    if (faltantes > 0) return faltantes;

    final DateTime ahora = DateTime.now();
    final EscritorZip zip = EscritorZip(ahora);
    final List<web.Blob> partes = [];
    final Map<Himnario, Map<String, HojaVersion>> versiones = {};

    // Se lee de a una: cada hoja pasa a la memoria del navegador y se suelta,
    // así los cientos de MB nunca están juntos en la memoria de la app.
    for (int i = 0; i < hojas.length; i++) {
      final (Himnario himnario, String ruta) = hojas[i];
      final Uint8List? datos = await RedWeb.leerGuardado(
        RedWeb.urlDeAsset(ruta),
      );
      if (datos == null) return 1; // se borró mientras se armaba el respaldo
      final String clave = DownloadService.claveDe(himnario, ruta);
      partes
        ..add(
          RedWeb.aBlob(zip.cabecera('${_carpeta(himnario)}$clave.webp', datos)),
        )
        ..add(RedWeb.aBlob(datos));
      versiones.putIfAbsent(himnario, () => {})[clave] = HojaVersion(
        await RedWeb.huellaDe(datos),
        datos.length,
      );
      onProgreso(i + 1, hojas.length);
    }

    for (final MapEntry<Himnario, Map<String, HojaVersion>> himnario
        in versiones.entries) {
      final Uint8List datos = utf8.encode(
        Manifiesto('', himnario.value).aJson(),
      );
      partes
        ..add(
          RedWeb.aBlob(
            zip.cabecera('${_carpeta(himnario.key)}versiones.json', datos),
          ),
        )
        ..add(RedWeb.aBlob(datos));
    }
    partes.add(RedWeb.aBlob(zip.cierre()));
    RedWeb.descargarArchivo(partes, nombreArchivo(ahora), 'application/zip');
    return 0;
  }

  /// Guarda en el dispositivo las hojas de un respaldo. Solo toma las hojas
  /// que cada himnario conoce y revisa cada una (CRC) antes de guardarla. Si
  /// el respaldo trae himnarios con términos que todavía no se aceptaron en
  /// este dispositivo, los pide con [aceptarTerminos]; los que no se acepten
  /// se dejan fuera. Si el respaldo es más viejo que lo publicado, la próxima
  /// revisión con internet baja solo las hojas que cambiaron.
  static Future<ResultadoRestauracion> restaurar(
    web.File archivo, {
    required void Function(int hechas, int total) onProgreso,
    required Future<bool> Function(Himnario himnario) aceptarTerminos,
  }) async {
    final int tamano = archivo.size;
    final IndiceZip? indice = buscarIndice(
      await RedWeb.leerTrozo(archivo, math.max(0, tamano - 65557), tamano),
    );
    if (indice == null) {
      throw const FormatException('El archivo no es un respaldo .zip válido.');
    }
    final List<EntradaZip> entradas = leerIndice(
      await RedWeb.leerTrozo(
        archivo,
        indice.inicio,
        indice.inicio + indice.tamano,
      ),
    );

    final Map<Himnario, Map<String, EntradaZip>> porHimnario = {};
    for (final EntradaZip entrada in entradas) {
      final RegExpMatch? hoja = _hoja.firstMatch(entrada.nombre);
      final Himnario? himnario = hoja == null
          ? null
          : _himnarioDe(hoja[1]!, hoja[2]!);
      if (himnario != null) {
        porHimnario.putIfAbsent(himnario, () => {})[hoja![3]!] = entrada;
      }
    }

    // Solo las hojas que el himnario conoce, de los himnarios con los
    // términos aceptados.
    final Map<Himnario, Map<String, String>> rutaPorClave = {};
    final List<(Himnario, String, EntradaZip)> pendientes = [];
    for (final MapEntry<Himnario, Map<String, EntradaZip>> grupo
        in porHimnario.entries) {
      final Himnario himnario = grupo.key;
      if (!await TerminosService.aceptados(himnario)) {
        if (!await aceptarTerminos(himnario)) continue;
        await TerminosService.aceptar(himnario);
      }
      final Map<String, String> rutas = {
        for (final String ruta in await DownloadService.todasLasRutas(himnario))
          DownloadService.claveDe(himnario, ruta): ruta,
      };
      rutaPorClave[himnario] = rutas;
      for (final MapEntry<String, EntradaZip> hoja in grupo.value.entries) {
        if (rutas.containsKey(hoja.key)) {
          pendientes.add((himnario, hoja.key, hoja.value));
        }
      }
    }
    if (pendientes.isEmpty) {
      throw FormatException(
        porHimnario.isEmpty
            ? 'El archivo no contiene hojas de ningún himnario.'
            : 'No se restauró ningún himnario.',
      );
    }

    final Map<Himnario, Map<String, HojaVersion>> restauradas = {};
    int danadas = 0;
    int hechas = 0;
    for (int i = 0; i < pendientes.length; i += _enParalelo) {
      await Future.wait(
        pendientes.skip(i).take(_enParalelo).map((hoja) async {
          final (Himnario himnario, String clave, EntradaZip entrada) = hoja;
          final Uint8List? datos = await _leerEntrada(archivo, entrada);
          if (datos == null) {
            danadas++;
          } else {
            await RedWeb.guardar(
              RedWeb.urlDeAsset(rutaPorClave[himnario]![clave]!),
              datos,
              'image/webp',
            );
            restauradas.putIfAbsent(himnario, () => {})[clave] = HojaVersion(
              await RedWeb.huellaDe(datos),
              datos.length,
            );
          }
          hechas++;
          onProgreso(hechas, pendientes.length);
        }),
      );
    }

    int faltantes = 0;
    for (final MapEntry<Himnario, Map<String, String>> grupo
        in rutaPorClave.entries) {
      final Himnario himnario = grupo.key;
      final Manifiesto? local = await ActualizacionService.leerLocalGuardado(
        himnario,
      );
      await ActualizacionService.guardarLocal(
        himnario,
        Manifiesto(local?.version ?? '', {
          ...?local?.hojas,
          ...?restauradas[himnario],
        }),
      );
      final List<bool> guardadas = await Future.wait(
        grupo.value.values.map(
          (ruta) => RedWeb.estaGuardado(RedWeb.urlDeAsset(ruta)),
        ),
      );
      final int faltan = guardadas.where((guardada) => !guardada).length;
      if (faltan == 0) await DownloadService.marcarDescargaCompleta(himnario);
      faltantes += faltan;
    }
    if (faltantes == 0) await RedWeb.pedirAlmacenamientoPersistente();
    final int total = restauradas.values.fold(
      0,
      (suma, hojas) => suma + hojas.length,
    );
    return ResultadoRestauracion(total, danadas, faltantes);
  }

  static Future<Uint8List?> _leerEntrada(
    web.File archivo,
    EntradaZip entrada,
  ) async {
    try {
      final int datos = inicioDatos(
        entrada,
        await RedWeb.leerTrozo(
          archivo,
          entrada.inicioCabecera,
          entrada.inicioCabecera + 30,
        ),
      );
      final web.Blob trozo = archivo.slice(
        datos,
        datos + entrada.tamanoComprimido,
      );
      final Uint8List contenido = switch (entrada.metodo) {
        0 => await RedWeb.leerTrozo(trozo, 0, entrada.tamanoComprimido),
        8 => await RedWeb.descomprimir(trozo),
        _ => Uint8List(0),
      };
      if (contenido.length != entrada.tamano ||
          crc32(contenido) != entrada.crc) {
        return null;
      }
      return contenido;
    } catch (_) {
      return null;
    }
  }
}
