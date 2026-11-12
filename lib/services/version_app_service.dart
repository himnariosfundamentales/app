import 'dart:js_interop';

import 'package:flutter/material.dart';

import '../screens/progreso_ui.dart';
import 'actualizacion_service.dart';
import 'red_web.dart';

// Definida en web/index.html: el service worker baja la versión nueva completa
// y después se recarga la página. 'error' si no se pudo.
@JS('himnarioActualizar')
external JSPromise<JSString> _himnarioActualizar();

/// Detecta si se publicó una versión nueva de la app. Cada publicación compila
/// la app con su commit (DESPLIEGUE) y deja el mismo valor en despliegue.txt
/// (ver .github/workflows/deploy.yml): si el publicado es otro, esta quedó
/// vieja. Sirve sobre todo para la app instalada que se queda abierta en
/// segundo plano, que no vuelve a cargar su código por sí sola.
class VersionAppService {
  /// La que se muestra al final de la Ayuda.
  static const String version = '1.12.1';

  static const String _despliegue = String.fromEnvironment('DESPLIEGUE');

  /// Queda en true al detectar una versión nueva: el menú ofrece "Actualizar
  /// APP" aunque el aviso se haya cerrado con "Después", y la pantalla
  /// principal esconde el botón de hojas pendientes, porque "Actualizar" también
  /// las baja.
  static final ValueNotifier<bool> versionNueva = ValueNotifier(false);

  static bool get versionNuevaDisponible => versionNueva.value;

  // La pantalla principal y el aviso preguntan al mismo tiempo al abrir la app:
  // comparten la misma consulta.
  static Future<bool>? _consulta;

  static Future<bool> hayVersionNueva() =>
      _consulta ??= _consultar().whenComplete(() => _consulta = null);

  static Future<bool> _consultar() async {
    // Compilación local, sin commit: no hay con qué comparar.
    if (_despliegue.isEmpty) return false;
    final String? publicado = await RedWeb.leerSinCache(
      RedWeb.urlDelSitio('despliegue.txt'),
    );
    final String? commit = publicado?.trim();
    final bool nueva =
        commit != null && commit.isNotEmpty && commit != _despliegue;
    if (nueva) versionNueva.value = true;
    return nueva;
  }

  /// Navegador de la app (ver main.dart): de él sale la ventana de avance de
  /// [actualizar], que se puede llamar desde el aviso o desde el menú.
  static final GlobalKey<NavigatorState> navegador = GlobalKey();

  /// La app abre con la versión guardada (ver web/sw.js): la nueva se baja
  /// completa aquí y se recarga. Mientras tanto una ventana muestra el avance,
  /// para que no parezca que no pasa nada; sin internet se dice y se queda la
  /// que está.
  static Future<void> actualizar(ScaffoldMessengerState? mensajes) async {
    mensajes?.hideCurrentMaterialBanner();
    final ValueNotifier<_Avance> avance = ValueNotifier(
      const _Avance('Revisando los himnos descargados…'),
    );
    final BuildContext? contexto = navegador.currentContext;
    final DialogoProgreso? ventana = contexto == null
        ? null
        : DialogoProgreso.abrir(
            contexto,
            (context) => AlertDialog(
              title: const Text('Actualizando la app'),
              content: ValueListenableBuilder<_Avance>(
                valueListenable: avance,
                builder: (context, paso, _) => Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(paso.texto),
                    const SizedBox(height: 12),
                    LinearProgressIndicator(value: paso.fraccion),
                    if (paso.detalle != null) ...[
                      const SizedBox(height: 8),
                      Text(paso.detalle!),
                    ],
                  ],
                ),
              ),
            ),
          );
    await _bajarHojasNuevas(avance);
    final String resultado;
    try {
      resultado = (await _himnarioActualizar().toDart).toDart;
    } catch (_) {
      // index.html de antes, sin himnarioActualizar.
      RedWeb.recargarPagina();
      return;
    }
    if (resultado == 'ok') return;
    ventana?.cerrar();
    mensajes?.showSnackBar(
      const SnackBar(
        content: Text(
          'No se pudo bajar la versión nueva. Revisa tu conexión e inténtalo otra vez.',
        ),
      ),
    );
  }

  // Las hojas que cambiaron en los himnarios descargados se bajan junto con la
  // app, antes de recargar: así la actualización es una sola y no hay que
  // aceptar después un segundo aviso para descargarlas. Si alguna falla, la
  // app nueva la ofrece al abrir, como siempre.
  static Future<void> _bajarHojasNuevas(ValueNotifier<_Avance> avance) async {
    try {
      final List<ActualizacionPendiente> pendientes = [
        for (final Revision revision
            in (await ActualizacionService.revisarTodos()).values)
          if (revision.pendiente != null) revision.pendiente!,
      ];
      final int total = pendientes.fold(
        0,
        (suma, pendiente) => suma + pendiente.hojas.length,
      );
      int anteriores = 0;
      for (final ActualizacionPendiente pendiente in pendientes) {
        final int base = anteriores;
        await ActualizacionService.aplicar(
          pendiente,
          onProgreso: (hechas, _) => avance.value = _Avance(
            'Bajando los himnos que cambiaron…',
            (base + hechas) / total,
            '${base + hechas} de $total hojas',
          ),
        );
        anteriores += pendiente.hojas.length;
      }
    } catch (_) {
      // Sin conexión o con algún error se sigue con la app: las hojas quedan
      // pendientes para después.
    }
    avance.value = const _Avance('Bajando la versión nueva…');
  }
}

/// Lo que muestra la ventana de [VersionAppService.actualizar]. Sin
/// [fraccion], la barra se mueve sin porcentaje.
class _Avance {
  final String texto;
  final double? fraccion;
  final String? detalle;

  const _Avance(this.texto, [this.fraccion, this.detalle]);
}
