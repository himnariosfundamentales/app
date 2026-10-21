import 'package:shared_preferences/shared_preferences.dart';
import '../models/himnario.dart';

/// Registro de los términos aceptados en este dispositivo. El himnario
/// principal no los pide.
class TerminosService {
  static String _key(Himnario himnario) => 'terminos_${himnario.id}';

  static Future<bool> aceptados(Himnario himnario) async {
    if (himnario.incluido) return true;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key(himnario)) ?? false;
  }

  /// Los de [himnarios] que ya se pueden abrir en este dispositivo.
  static Future<Set<Himnario>> aceptadosDe(
    Iterable<Himnario> himnarios,
  ) async => {
    for (final Himnario himnario in himnarios)
      if (await aceptados(himnario)) himnario,
  };

  static Future<void> aceptar(Himnario himnario) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key(himnario), true);
  }
}
