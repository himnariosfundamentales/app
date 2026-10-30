import 'dart:ui' show Color;

import '../models/himnario.dart';
import '../models/himno.dart';
import 'busqueda.dart';
import 'himnos_bautista.dart';
import 'himnos_celebremos.dart';
import 'himnos_gracia.dart';
import 'himnos_majestuoso.dart';
import 'himnos_ministerio.dart';
import 'himnos_navidenno.dart';
import 'himnos_popular.dart';

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

  static final Himnario navidenno = Himnario(
    id: 'navidenno',
    nombre: 'Himnario Navideño Bautista',
    prefijo: 'N',
    incluido: true,
    color: const Color(0xFF0B2C0E),
    himnos: himnosNavidenno,
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

  static final Himnario bautista = Himnario(
    id: 'bautista',
    nombre: 'Himnario Bautista',
    prefijo: 'B',
    incluido: false,
    color: const Color(0xFFB2382D),
    himnos: himnosBautista,
  );

  static final Himnario popular = Himnario(
    id: 'popular',
    nombre: 'El Nuevo Himnario Popular',
    prefijo: 'P',
    incluido: false,
    color: const Color(0xFF153273),
    himnos: himnosPopular,
  );

  static final List<Himnario> todos = [
    ministerio,
    navidenno,
    majestuoso,
    gracia,
    celebremos,
    bautista,
    popular,
  ];

  static Himnario? porId(String id) {
    for (final Himnario himnario in todos) {
      if (himnario.id == id) return himnario;
    }
    return null;
  }

  // Número solo ("11") o con la letra de un himnario ("M11", "g 11").
  static final RegExp _numeroConLetra = RegExp(r'^([a-zA-Z]?)\s*(\d+)$');

  /// Búsqueda en todos los himnarios. Un número solo busca en todos y con
  /// letra solo en ese himnario ("M11" es el 11 de Himnos Majestuosos); los
  /// exactos van primero (el 11, M11, G11... antes que el 110 o el 211). Un
  /// texto busca en los títulos de todos, ordenados por nombre o, con
  /// [porNumero], por número.
  ///
  /// Dentro de un himnario ([actual]) sus himnos van primero; con un número,
  /// primero entre los exactos y luego entre los demás.
  static List<HimnoEncontrado> buscar(
    String texto, {
    Himnario? actual,
    bool porNumero = false,
  }) {
    final String consulta = texto.trim();
    if (consulta.isEmpty) return const [];

    final RegExpMatch? numero = _numeroConLetra.firstMatch(consulta);
    if (numero == null) {
      return _suyosPrimero([
        for (final Himnario himnario in todos)
          for (final Himno himno in buscarEn(
            consulta,
            porNumero ? himnario.himnosPorNumero : himnario.himnosPorNombre,
          ))
            HimnoEncontrado(himnario, himno),
      ], actual);
    }

    final String letra = numero[1]!.toUpperCase();
    // Una letra que no es de ningún himnario ("X11"): no hay resultados.
    final List<HimnoEncontrado> encontrados = [
      for (final Himnario himnario in todos)
        if (letra.isEmpty || himnario.prefijo == letra)
          ..._porNumero(himnario, numero[2]!),
    ];
    final int? exacto = int.tryParse(numero[2]!);
    return [
      ..._suyosPrimero(
        encontrados.where((encontrado) => encontrado.himno.numero == exacto),
        actual,
      ),
      ..._suyosPrimero(
        encontrados.where((encontrado) => encontrado.himno.numero != exacto),
        actual,
      ),
    ];
  }

  // Los de [actual] primero; sin él, en el orden en que vienen.
  static List<HimnoEncontrado> _suyosPrimero(
    Iterable<HimnoEncontrado> lista,
    Himnario? actual,
  ) => [
    ...lista.where((encontrado) => encontrado.himnario == actual),
    ...lista.where((encontrado) => encontrado.himnario != actual),
  ];

  // Los de [himnario] cuyo número contiene [digitos], el exacto primero.
  static List<HimnoEncontrado> _porNumero(Himnario himnario, String digitos) =>
      [
        for (final Himno himno in buscarEn(digitos, himnario.himnosPorNumero))
          if (himno.numero.toString().contains(digitos))
            HimnoEncontrado(himnario, himno),
      ];
}
