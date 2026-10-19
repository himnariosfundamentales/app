import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;
import '../services/red_web.dart';
import '../services/respaldo_service.dart';
import 'progreso_ui.dart';
import 'terminos_ui.dart';

/// Guardar y restaurar el respaldo de los himnarios descargados, con su
/// diálogo de progreso. Se usa desde el menú de la pantalla principal y desde
/// la pantalla de bienvenida.
class RespaldoUi {
  static Future<void> guardar(BuildContext context) async {
    final ScaffoldMessengerState mensajes = ScaffoldMessenger.of(context);
    if ((await RespaldoService.himnariosDescargados()).isEmpty) {
      mensajes.showSnackBar(
        const SnackBar(
          content: Text(
            'Primero descarga algún himnario completo para poder respaldarlo.',
          ),
        ),
      );
      return;
    }
    if (!context.mounted) return;
    final int faltantes;
    try {
      faltantes = await _conProgreso(
        context,
        'Preparando respaldo',
        (onProgreso) => RespaldoService.guardar(onProgreso: onProgreso),
      );
    } catch (_) {
      mensajes.showSnackBar(
        const SnackBar(
          content: Text('No se pudo crear el respaldo. Inténtalo de nuevo.'),
        ),
      );
      return;
    }
    mensajes.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 8),
        content: Text(
          faltantes == 0
              ? 'Respaldo listo: ${RespaldoService.nombreArchivo(DateTime.now())}. '
                    'Consérvalo, sirve para restaurar los himnarios sin internet.'
              : 'Faltan $faltantes hojas en este dispositivo. Usa "Verificar '
                    'descargas" y vuelve a intentarlo.',
        ),
      ),
    );
  }

  /// Devuelve el resultado, o null si no se eligió archivo o no era válido.
  static Future<ResultadoRestauracion?> restaurar(BuildContext context) async {
    // Sin esperas antes: el navegador solo abre el selector durante un toque.
    final web.File? archivo = await RedWeb.elegirArchivo(
      '.zip,application/zip',
    );
    if (archivo == null || !context.mounted) return null;

    final ScaffoldMessengerState mensajes = ScaffoldMessenger.of(context);
    try {
      final ResultadoRestauracion resultado = await _conProgreso(
        context,
        'Restaurando himnarios',
        (onProgreso) => RespaldoService.restaurar(
          archivo,
          onProgreso: onProgreso,
          aceptarTerminos: (himnario) =>
              TerminosUi.pedir(context, himnario, accion: 'Restaurar'),
        ),
      );
      final String danadas = resultado.danadas == 0
          ? ''
          : ' ${resultado.danadas} venían dañadas.';
      mensajes.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 8),
          content: Text(
            resultado.faltantes == 0
                ? 'Himnarios restaurados (${resultado.restauradas} hojas).$danadas'
                : 'Se restauraron ${resultado.restauradas} hojas; faltan '
                      '${resultado.faltantes}. Descárgalas con internet desde '
                      '"Verificar descargas".$danadas',
          ),
        ),
      );
      return resultado;
    } catch (e) {
      if (context.mounted) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('No se pudo restaurar'),
            content: Text(
              e is FormatException
                  ? e.message
                  : 'El archivo está dañado o el dispositivo no tiene espacio '
                        'suficiente.',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Entendido'),
              ),
            ],
          ),
        );
      }
      return null;
    }
  }

  static Future<T> _conProgreso<T>(
    BuildContext context,
    String titulo,
    Future<T> Function(void Function(int hechas, int total) onProgreso) tarea,
  ) async {
    final ValueNotifier<(int, int)> avance = ValueNotifier((0, 0));
    final DialogoProgreso progreso = DialogoProgreso.abrir(
      context,
      (context) => AlertDialog(
        title: Text(titulo),
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
              ],
            );
          },
        ),
      ),
    );
    try {
      return await tarea((hechas, total) => avance.value = (hechas, total));
    } finally {
      progreso.cerrar();
      avance.dispose();
    }
  }
}
