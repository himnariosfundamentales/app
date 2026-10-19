import 'package:flutter/material.dart';

/// Diálogo de progreso que no se puede cerrar a mano. [cerrar] quita este
/// diálogo aunque después se haya abierto otro encima: un `pop` cerraría el
/// de arriba y este quedaría abierto para siempre.
class DialogoProgreso {
  final NavigatorState _navegador;
  final DialogRoute<void> _ruta;

  DialogoProgreso._(this._navegador, this._ruta);

  static DialogoProgreso abrir(BuildContext context, WidgetBuilder builder) {
    final NavigatorState navegador = Navigator.of(context, rootNavigator: true);
    final DialogRoute<void> ruta = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      themes: InheritedTheme.capture(from: context, to: navegador.context),
      builder: (context) => PopScope(canPop: false, child: builder(context)),
    );
    navegador.push(ruta);
    return DialogoProgreso._(navegador, ruta);
  }

  void cerrar() {
    if (_ruta.isActive) _navegador.removeRoute(_ruta);
  }
}
