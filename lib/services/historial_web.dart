import 'dart:async';
import 'dart:ui' as ui;
import 'dart:ui_web' as ui_web;

/// Manejo del historial del navegador para que el botón (o el gesto) de
/// atrás de Android no cierre la app.
///
/// Flutter mantiene una entrada propia encima de la de la app para enterarse
/// de cada "atrás", y al presionarlo la vuelve a agregar. Chrome se salta las
/// entradas agregadas sin que el usuario haya tocado la página: un segundo
/// "atrás" seguido se saltaba la app y la cerraba (por ejemplo, de un himno al
/// himnario y de ahí a la pantalla principal). Aquí, en lugar de agregarla
/// otra vez, se avanza a la que ya estaba, porque avanzar no cuenta como
/// agregar. Por lo demás es igual que la de Flutter (la URL con #).
class HistorialWeb implements ui_web.UrlStrategy {
  static const ui_web.HashUrlStrategy _base = ui_web.HashUrlStrategy();

  // Mientras Flutter atiende un "atrás".
  bool _atendiendoAtras = false;
  // El avance a la entrada que ya estaba; su evento no se le pasa a Flutter,
  // que ya la da por agregada.
  Completer<void>? _avance;

  @override
  ui.VoidCallback addPopStateListener(ui_web.PopStateListener fn) =>
      _base.addPopStateListener((Object? state) {
        final Completer<void>? avance = _avance;
        if (avance != null && !avance.isCompleted) {
          avance.complete();
          return;
        }
        _atendiendoAtras = true;
        try {
          fn(state);
        } finally {
          _atendiendoAtras = false;
        }
      });

  @override
  void pushState(Object? state, String title, String url) {
    if (!_atendiendoAtras) {
      _base.pushState(state, title, url);
      return;
    }
    final Completer<void> avance = _avance = Completer<void>();
    _base.go(1).then((_) {
      if (!avance.isCompleted) avance.complete();
    });
    // Si no había a dónde avanzar, se agrega como siempre.
    Timer(const Duration(milliseconds: 500), () {
      if (avance.isCompleted) return;
      avance.complete();
      _base.pushState(state, title, url);
    });
  }

  @override
  Future<void> go(int count) async {
    // Al salir de la app Flutter retrocede: primero tiene que terminar el
    // avance pendiente, o se cruzarían.
    await _avance?.future;
    return _base.go(count);
  }

  @override
  String getPath() => _base.getPath();

  @override
  Object? getState() => _base.getState();

  @override
  String prepareExternalUrl(String internalUrl) =>
      _base.prepareExternalUrl(internalUrl);

  @override
  void replaceState(Object? state, String title, String url) =>
      _base.replaceState(state, title, url);
}
