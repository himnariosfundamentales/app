import 'package:flutter/material.dart';
import '../models/himnario.dart';

/// Términos que se aceptan antes de descargar un himnario que no viene
/// incluido en la app.
class TerminosUi {
  static const List<String> _resumen = [
    'Tengo un ejemplar físico de este himnario. La versión digital es solo mi copia de respaldo y de uso práctico.',
    'Los derechos de letras, música y arreglos siguen siendo de sus dueños, editores y representantes legales.',
    'Me hago responsable de darle buen uso: únicamente con fines educativos o ministeriales, sin compartirlo con personas que no tengan su propio ejemplar físico.',
  ];

  static const List<(String, String)> _completo = [
    (
      'Copia de respaldo',
      'Este himnario se ofrece únicamente como copia digital de respaldo para quienes ya tienen el himnario impreso. Solo deberías descargarlo si tienes tu propio ejemplar físico.',
    ),
    (
      'Derechos de autor',
      'Los himnos, letras, música, arreglos, traducciones y el diseño del himnario siguen siendo propiedad de sus autores, compositores, editores y de quienes los representan legalmente, así como de los dueños de las obras originales. Descargarlo no te transfiere ningún derecho sobre ellos ni sustituye la compra del himnario.',
    ),
    (
      'Uso permitido',
      'La copia digital es solo para uso personal, educativo o ministerial, por ejemplo para cantar o ensayar en tu congregación. No está permitido venderla, reproducirla para repartirla ni publicarla.',
    ),
    (
      'Responsabilidad',
      'Quien descarga el himnario se hace responsable de darle buen uso y de no compartirlo ni difundirlo con personas que no tengan una versión física.',
    ),
    (
      'Aceptación',
      'Al aceptar confirmas que tienes un ejemplar físico de este himnario y que estás de acuerdo con estos términos.',
    ),
  ];

  /// Muestra los términos de [himnario]. Devuelve true si se aceptan con
  /// [accion] ("Descargar" o "Restaurar").
  static Future<bool> pedir(
    BuildContext context,
    Himnario himnario, {
    String accion = 'Descargar',
  }) async {
    bool completo = false;
    final bool? aceptados = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(himnario.nombre),
          scrollable: true,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Términos de uso',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              Text('Al ${accion.toLowerCase()} este himnario, declaro que:'),
              const SizedBox(height: 8),
              for (final String punto in _resumen)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('•  '),
                      Expanded(child: Text(punto)),
                    ],
                  ),
                ),
              if (!completo)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    style: TextButton.styleFrom(padding: EdgeInsets.zero),
                    onPressed: () => setState(() => completo = true),
                    child: const Text('Leer más...'),
                  ),
                )
              else
                for (final (String titulo, String texto) in _completo)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          titulo,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        Text(texto),
                      ],
                    ),
                  ),
              const SizedBox(height: 8),
              Text(
                'SI NO TIENES ESTE HIMNARIO EN FÍSICO, POR FAVOR NO LO DESCARGUES.',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(accion),
            ),
          ],
        ),
      ),
    );
    return aceptados ?? false;
  }
}
