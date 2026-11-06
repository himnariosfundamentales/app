import 'dart:js_interop';

import 'package:flutter/material.dart';

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
  static const String version = '1.10.0';

  static const String _despliegue = String.fromEnvironment('DESPLIEGUE');

  /// Queda en true al detectar una versión nueva: el menú ofrece "Actualizar
  /// APP" aunque el aviso se haya cerrado con "Después".
  static bool versionNuevaDisponible = false;

  static Future<bool> hayVersionNueva() async {
    // Compilación local, sin commit: no hay con qué comparar.
    if (_despliegue.isEmpty) return false;
    final String? publicado = await RedWeb.leerSinCache(
      RedWeb.urlDelSitio('despliegue.txt'),
    );
    final String? commit = publicado?.trim();
    final bool nueva =
        commit != null && commit.isNotEmpty && commit != _despliegue;
    if (nueva) versionNuevaDisponible = true;
    return nueva;
  }

  /// La app abre con la versión guardada (ver web/sw.js): la nueva se baja
  /// completa aquí y se recarga. Mientras tanto se avisa en [mensajes]; sin
  /// internet se dice y se queda la que está.
  static Future<void> actualizar(ScaffoldMessengerState? mensajes) async {
    mensajes?.hideCurrentMaterialBanner();
    mensajes?.showSnackBar(
      const SnackBar(
        content: Text('Bajando la versión nueva…'),
        duration: Duration(minutes: 2),
      ),
    );
    final String resultado;
    try {
      resultado = (await _himnarioActualizar().toDart).toDart;
    } catch (_) {
      // index.html de antes, sin himnarioActualizar.
      RedWeb.recargarPagina();
      return;
    }
    if (resultado == 'ok') return;
    mensajes
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text(
            'No se pudo bajar la versión nueva. Revisa tu conexión e inténtalo otra vez.',
          ),
        ),
      );
  }
}
