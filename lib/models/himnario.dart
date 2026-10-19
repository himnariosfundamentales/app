import 'dart:ui' show Color;

import 'himno.dart';

/// Un himnario de la app. Sus hojas están en `assets/himnarios/<id>/`.
class Himnario {
  final String id;
  final String nombre;

  /// Letra que va antes del número en el buscador general ("M11"). Vacía en
  /// el himnario principal: "11" es su himno 11.
  final String prefijo;

  /// El principal viene incluido; los demás piden aceptar los términos antes
  /// de descargarlos.
  final bool incluido;

  /// Color de su portada: lo llevan sus números en las listas.
  final Color color;

  final List<Himno> himnos;

  Himnario({
    required this.id,
    required this.nombre,
    required this.prefijo,
    required this.incluido,
    required this.color,
    required this.himnos,
  });

  String get carpeta => 'assets/himnarios/$id/';

  String get portada => '${carpeta}portada.webp';

  /// "M11" en los himnarios con letra, "11" en el principal.
  String etiqueta(int numero) => '$prefijo$numero';

  /// Dentro del himnario, "M11" busca lo mismo que "11".
  String quitarPrefijo(String texto) {
    final String limpio = texto.trim();
    if (prefijo.isEmpty ||
        !RegExp('^$prefijo\\s*\\d+\$', caseSensitive: false).hasMatch(limpio)) {
      return texto;
    }
    return limpio.substring(prefijo.length).trim();
  }

  late final List<Himno> himnosPorNumero = [...himnos]
    ..sort((a, b) => a.numero.compareTo(b.numero));

  late final List<Himno> himnosPorNombre = [...himnos]
    ..sort((a, b) => a.claveOrden.compareTo(b.claveOrden));
}
