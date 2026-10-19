import 'dart:async';

import 'package:flutter/material.dart';
import '../models/himnario.dart';
import '../services/actualizacion_service.dart';
import '../services/download_service.dart';
import '../services/red_web.dart';
import '../services/terminos_service.dart';
import 'progreso_ui.dart';
import 'terminos_ui.dart';

/// Descarga de un himnario desde la pantalla principal, con su diálogo de
/// progreso. Si el himnario pide términos, los muestra antes.
class DescargaUi {
  /// Devuelve false si no se aceptaron los términos; true si se aceptaron
  /// (aunque la descarga haya quedado incompleta: el himnario se puede usar
  /// con internet y completar después).
  static Future<bool> descargar(BuildContext context, Himnario himnario) async {
    if (!await TerminosService.aceptados(himnario)) {
      if (!context.mounted || !await TerminosUi.pedir(context, himnario)) {
        return false;
      }
      await TerminosService.aceptar(himnario);
    }
    if (!context.mounted) return true;

    final ScaffoldMessengerState mensajes = ScaffoldMessenger.of(context);
    final ValueNotifier<(int, int)> avance = ValueNotifier((0, 0));
    // Se conoce al leer versiones.json, antes de la primera hoja.
    String? peso;
    final DialogoProgreso progreso = DialogoProgreso.abrir(
      context,
      (context) => AlertDialog(
        title: Text('Descargando ${himnario.nombre}'),
        content: ValueListenableBuilder<(int, int)>(
          valueListenable: avance,
          builder: (context, valor, _) {
            final (int hechas, int total) = valor;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(
                  value: total == 0 ? null : hechas / total,
                ),
                const SizedBox(height: 12),
                Text(total == 0 ? 'Preparando...' : '$hechas de $total hojas'),
                if (peso != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Peso aproximado: $peso',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );

    // Se lee antes de descargar: si se publica algo a mitad de la descarga,
    // la próxima revisión lo detecta como actualización.
    final Manifiesto? manifiesto = await ActualizacionService.leerRemoto(
      himnario,
    );
    final int bytes =
        manifiesto?.hojas.values.fold<int>(0, (suma, h) => suma + h.bytes) ?? 0;
    if (bytes > 0) peso = _megas(bytes);
    final int fallidas = await DownloadService.descargar(
      himnario,
      huellasPublicadas: manifiesto == null
          ? null
          : {
              for (final MapEntry<String, HojaVersion> hoja
                  in manifiesto.hojas.entries)
                hoja.key: hoja.value.hash,
            },
      onProgreso: (hechas, total) => avance.value = (hechas, total),
    );
    if (fallidas == 0) {
      unawaited(RedWeb.pedirAlmacenamientoPersistente());
      unawaited(RedWeb.guardarArchivosDeLaApp());
      if (manifiesto != null) {
        await ActualizacionService.guardarLocal(himnario, manifiesto);
      }
    }
    progreso.cerrar();
    avance.dispose();
    mensajes.showSnackBar(
      SnackBar(
        content: Text(
          fallidas == 0
              ? '${himnario.nombre} quedó descargado: ya funciona sin internet.'
              : 'No se pudieron descargar $fallidas hojas. Revisa tu conexión e '
                    'inténtalo de nuevo.',
        ),
      ),
    );
    return true;
  }

  static String _megas(int bytes) {
    final double mb = bytes / 1e6;
    return '≈${mb < 10 ? mb.toStringAsFixed(1) : mb.round()} MB';
  }
}
