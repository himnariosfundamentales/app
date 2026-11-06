import 'dart:ui' show Color;

import 'himno.dart';

/// En qué afinación o clave están escritas las partituras de un himnario: en
/// Do, la de siempre, transportadas para los instrumentos en Si♭ o en Fa, o en
/// clave de Do para viola.
enum Afinacion {
  enDo('Do', 'Partituras en Do: voz, piano, guitarra'),
  enSiBemol('Si♭', 'Partituras para instrumentos en Si♭: trompeta, clarinete'),
  enFa('Fa', 'Partituras para instrumentos en Fa: corno francés'),
  claveDeDo('Clave de Do', 'Partituras en clave de Do: viola');

  final String nombre;
  final String descripcion;

  const Afinacion(this.nombre, this.descripcion);
}

/// Un himnario de la app. Sus hojas están en `assets/himnarios/<id>/`.
class Himnario {
  final String id;
  final String nombre;

  /// Letra que va antes del número en el buscador general ("M11"). Vacía en
  /// el himnario principal: "11" es su himno 11. Solo se busca entre los de
  /// la misma afinación, así que basta con que no se repita dentro de una.
  final String prefijo;

  /// El principal viene incluido; los demás piden aceptar los términos antes
  /// de descargarlos.
  final bool incluido;

  /// Color de su portada: lo llevan sus números en las listas.
  final Color color;

  final List<Himno> himnos;

  /// En modo libro, las hojas (por su clave, como "2-1") que llevan antes una
  /// página en blanco, para que cada una quede del lado que tiene en el libro
  /// impreso. Normalmente solo la primera, que va a la derecha como la
  /// primera página de un libro; también donde se quitó una página suelta.
  final Set<String> blancosAntes;

  /// En el inicio se ven y se buscan solo los de la afinación elegida; dentro
  /// de un himnario, los de la suya.
  final Afinacion afinacion;

  Himnario({
    required this.id,
    required this.nombre,
    required this.prefijo,
    required this.incluido,
    required this.color,
    required this.himnos,
    this.blancosAntes = const {'1-1'},
    this.afinacion = Afinacion.enDo,
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
