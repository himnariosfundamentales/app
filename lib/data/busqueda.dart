import '../models/himno.dart';

/// Himnos de [lista] cuyo número o título contiene [texto], sin importar
/// acentos, mayúsculas ni signos. El número exacto va primero: al escribir
/// "64" aparece el 64 antes que el 164 o el 264.
List<Himno> buscarEn(String texto, List<Himno> lista) {
  final String consulta = normalizar(texto);
  if (consulta.isEmpty) return lista;
  final int? exacto = int.tryParse(consulta);
  final List<Himno> encontrados = lista
      .where(
        (himno) =>
            himno.numero.toString().contains(consulta) ||
            normalizar(himno.nombre).contains(consulta),
      )
      .toList();
  return [
    ...encontrados.where((h) => h.numero == exacto),
    ...encontrados.where((h) => h.numero != exacto),
  ];
}

// Sin acentos ni signos (¿, ¡, comas) y con la ñ después de la n: sirve
// para ordenar como diccionario y para buscar sin importar acentos.
String normalizar(String nombre) {
  const conAcento = 'áéíóúü';
  const sinAcento = 'aeiouu';
  final buffer = StringBuffer();
  for (final letra in nombre.toLowerCase().split('')) {
    final i = conAcento.indexOf(letra);
    if (i >= 0) {
      buffer.write(sinAcento[i]);
    } else if (letra == 'ñ') {
      buffer.write('n\u007f');
    } else if (RegExp(r'[a-z0-9 ]').hasMatch(letra)) {
      buffer.write(letra);
    }
  }
  return buffer.toString().replaceAll(RegExp(r' +'), ' ').trim();
}
