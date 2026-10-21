import 'dart:ui' show Color;

import '../models/himnario.dart';
import '../models/himno.dart';
import 'busqueda.dart';
import 'himnos_celebremos.dart';
import 'himnos_gracia.dart';
import 'himnos_majestuoso.dart';
import 'himnos_ministerio.dart';

/// Un himno junto con el himnario al que pertenece.
class HimnoEncontrado {
  final Himnario himnario;
  final Himno himno;

  const HimnoEncontrado(this.himnario, this.himno);
}

class Catalogo {
  static final Himnario ministerio = Himnario(
    id: 'ministerio',
    nombre: 'Himnario Ministerio Musical',
    prefijo: '',
    incluido: true,
    color: const Color(0xFF0175C2),
    himnos: himnosMinisterio,
  );

  static final Himnario majestuoso = Himnario(
    id: 'majestuoso',
    nombre: 'Himnos Majestuosos',
    prefijo: 'M',
    incluido: false,
    color: const Color(0xFF501018),
    himnos: himnosMajestuoso,
  );

  static final Himnario gracia = Himnario(
    id: 'gracia',
    nombre: 'Himnos de Gracia',
    prefijo: 'G',
    incluido: false,
    color: const Color(0xFF1C242C),
    himnos: himnosGracia,
  );

  static final Himnario celebremos = Himnario(
    id: 'celebremos',
    nombre: 'Celebremos su Gloria',
    prefijo: 'C',
    incluido: false,
    color: const Color(0xFFB85C1E),
    himnos: himnosCelebremos,
    // La primera hoja va a la izquierda en el libro, y antes de estas había
    // una portadilla de sección que no se incluyó.
    blancosAntes: const {
      '2-1',
      '110-1',
      '249-1',
      '268-1_269-1',
      '286-1',
      '351-1',
      '448-1',
      '543-1',
      '572-1',
      '624-1_625-1',
    },
  );

  static final List<Himnario> todos = [
    ministerio,
    majestuoso,
    gracia,
    celebremos,
  ];

  static Himnario? porId(String id) {
    for (final Himnario himnario in todos) {
      if (himnario.id == id) return himnario;
    }
    return null;
  }

  // Número solo ("11") o con la letra de un himnario ("M11", "g 11").
  static final RegExp _numeroConLetra = RegExp(r'^([a-zA-Z]?)\s*(\d+)$');

  /// Búsqueda en todos los himnarios. Un número solo busca en el principal y
  /// con letra en ese himnario ("M11" es el 11 de Himnos Majestuosos); un
  /// texto busca en los títulos de todos.
  static List<HimnoEncontrado> buscar(String texto) {
    final String consulta = texto.trim();
    if (consulta.isEmpty) return const [];

    final RegExpMatch? numero = _numeroConLetra.firstMatch(consulta);
    if (numero != null) {
      final String letra = numero[1]!.toUpperCase();
      for (final Himnario himnario in todos) {
        if (himnario.prefijo == letra) {
          return [
            for (final Himno himno in buscarEn(
              numero[2]!,
              himnario.himnosPorNumero,
            ))
              if (himno.numero.toString().contains(numero[2]!))
                HimnoEncontrado(himnario, himno),
          ];
        }
      }
      // Una letra que no es de ningún himnario ("X11"): no hay resultados.
      if (letra.isNotEmpty) return const [];
    }

    return [
      for (final Himnario himnario in todos)
        for (final Himno himno in buscarEn(consulta, himnario.himnosPorNombre))
          HimnoEncontrado(himnario, himno),
    ];
  }
}
