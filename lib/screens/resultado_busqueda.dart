import 'package:flutter/material.dart';
import '../data/catalogo.dart';

/// Un himno en la lista de un buscador, con el nombre de su himnario debajo.
/// Los de otro himnario llevan su letra ("M11") y, si todavía no se pueden
/// abrir, el ícono de descarga.
class ResultadoBusqueda extends StatelessWidget {
  final HimnoEncontrado encontrado;

  /// Es del himnario en que se busca: va solo con su número.
  final bool propio;
  final bool aceptado;

  /// Sin búsqueda, en la lista de un solo himnario, el nombre sobra.
  final bool conHimnario;
  final VoidCallback onTap;

  const ResultadoBusqueda({
    super.key,
    required this.encontrado,
    this.propio = false,
    this.aceptado = true,
    this.conHimnario = true,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final himnario = encontrado.himnario;
    final himno = encontrado.himno;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: himnario.color,
        foregroundColor: Colors.white,
        child: propio
            ? Text('${himno.numero}')
            : Padding(
                padding: const EdgeInsets.all(4),
                child: FittedBox(child: Text(himnario.etiqueta(himno.numero))),
              ),
      ),
      title: Text(himno.nombre),
      subtitle: conHimnario ? Text(himnario.nombre) : null,
      trailing: aceptado
          ? null
          : const Icon(Icons.download, color: Colors.grey),
      onTap: onTap,
    );
  }
}
