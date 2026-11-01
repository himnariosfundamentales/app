import 'package:shared_preferences/shared_preferences.dart';
import '../data/catalogo.dart';
import '../models/himnario.dart';

/// La afinación elegida en la pantalla principal: se recuerda al volver a
/// abrir la app.
class AfinacionService {
  static const String _key = 'afinacion';

  /// Si la guardada ya no tiene himnarios, vuelve a Do.
  static Future<Afinacion> elegida() async {
    final prefs = await SharedPreferences.getInstance();
    final Afinacion? guardada = Afinacion.values
        .asNameMap()[prefs.getString(_key)];
    return guardada != null && Catalogo.afinaciones.contains(guardada)
        ? guardada
        : Afinacion.enDo;
  }

  static Future<void> elegir(Afinacion afinacion) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, afinacion.name);
  }
}
