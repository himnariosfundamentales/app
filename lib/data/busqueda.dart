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
            himno.claveBusqueda.contains(consulta),
      )
      .toList();
  return [
    ...encontrados.where((h) => h.numero == exacto),
    ...encontrados.where((h) => h.numero != exacto),
  ];
}

/// Para buscar: minúsculas, sin acentos y con la ñ como n ("senor" encuentra
/// "Señor").
String normalizar(String texto) => _limpiar(texto, 'n');

/// Para ordenar como diccionario: igual que [normalizar], pero con la ñ
/// después de la n.
String claveDeOrden(String nombre) => _limpiar(nombre, 'n\u007f');

const String _conAcento = 'áéíóúü';
const String _sinAcento = 'aeiouu';
final RegExp _espacios = RegExp(r' +');

// Los signos (¿, ¡, comas, "90:1-2") pasan a ser espacios para que los
// números no se junten: "Salmo 90:1-2" no debe aparecer al buscar "12".
String _limpiar(String texto, String enie) {
  final StringBuffer buffer = StringBuffer();
  for (final String letra in texto.toLowerCase().split('')) {
    final int i = _conAcento.indexOf(letra);
    final int codigo = letra.codeUnitAt(0);
    if (i >= 0) {
      buffer.write(_sinAcento[i]);
    } else if (letra == 'ñ') {
      buffer.write(enie);
    } else if ((codigo >= 0x61 && codigo <= 0x7a) ||
        (codigo >= 0x30 && codigo <= 0x39)) {
      buffer.write(letra);
    } else {
      buffer.write(' ');
    }
  }
  return buffer.toString().replaceAll(_espacios, ' ').trim();
}
