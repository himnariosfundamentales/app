import 'dart:async';

import 'package:flutter/material.dart';
import '../data/catalogo.dart';
import '../services/actualizacion_service.dart';
import '../services/download_service.dart';
import '../services/red_web.dart';
import '../services/respaldo_service.dart';
import 'inicio_screen.dart';
import 'respaldo_ui.dart';

/// Bienvenida la primera vez: ofrece descargar el himnario principal para
/// usarlo sin internet.
class DescargaScreen extends StatefulWidget {
  const DescargaScreen({super.key});

  @override
  State<DescargaScreen> createState() => _DescargaScreenState();
}

class _DescargaScreenState extends State<DescargaScreen> {
  int _completados = 0;
  int _total = 0;
  bool _descargando = false;
  bool _huboFallos = false;
  String _estado =
      'Para usar el Himnario Ministerio Musical sin internet, es necesario descargarlo en este dispositivo (cerca de 30 MB, se recomienda usar Wi-Fi).';

  Future<void> _iniciarDescarga() async {
    setState(() {
      _descargando = true;
      _huboFallos = false;
      _completados = 0;
      _estado = 'Descargando el himnario a la memoria local...';
    });

    // Se lee antes de descargar: si se publica algo a mitad de la descarga,
    // la próxima revisión lo detecta como actualización.
    final Manifiesto? manifiesto = await ActualizacionService.leerRemoto(
      Catalogo.ministerio,
    );
    final int fallidos = await DownloadService.descargar(
      Catalogo.ministerio,
      huellasPublicadas: manifiesto == null
          ? null
          : {
              for (final MapEntry<String, HojaVersion> hoja
                  in manifiesto.hojas.entries)
                hoja.key: hoja.value.hash,
            },
      onProgreso: (completados, total) {
        if (!mounted) return;
        setState(() {
          _completados = completados;
          _total = total;
        });
      },
    );

    if (!mounted) return;

    if (fallidos == 0) {
      unawaited(RedWeb.pedirAlmacenamientoPersistente());
      if (manifiesto != null) {
        await ActualizacionService.guardarLocal(
          Catalogo.ministerio,
          manifiesto,
        );
      }
      if (mounted) _irAlInicio();
      return;
    }

    setState(() {
      _descargando = false;
      _huboFallos = true;
      _estado =
          'No se pudieron descargar $fallidos de $_total hojas. Revisa tu conexión e inténtalo de nuevo.';
    });
  }

  void _irAlInicio() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const InicioScreen()),
    );
  }

  // Con el respaldo completo se entra directo a la pantalla principal, igual
  // que al terminar la descarga; si faltan hojas se queda aquí para
  // descargarlas.
  Future<void> _restaurar() async {
    final ResultadoRestauracion? resultado = await RespaldoUi.restaurar(
      context,
    );
    if (resultado != null && resultado.faltantes == 0 && mounted) _irAlInicio();
  }

  @override
  Widget build(BuildContext context) {
    double progreso = _total > 0 ? _completados / _total : 0.0;

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.cloud_download, size: 80, color: Colors.blue),
              const SizedBox(height: 24),
              const Text(
                'Bienvenido al Himnario',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                _estado,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: _huboFallos
                      ? Theme.of(context).colorScheme.error
                      : Colors.grey,
                ),
              ),
              const SizedBox(height: 32),

              if (_descargando) ...[
                LinearProgressIndicator(value: progreso, minHeight: 10),
                const SizedBox(height: 16),
                Text(
                  _total == 0
                      ? 'Preparando...'
                      : 'Descargado: $_completados de $_total hojas (${(progreso * 100).toInt()}%)',
                ),
              ] else ...[
                ElevatedButton.icon(
                  onPressed: _iniciarDescarga,
                  icon: Icon(_huboFallos ? Icons.refresh : Icons.download),
                  label: Text(
                    _huboFallos
                        ? 'Reintentar descarga'
                        : 'Descargar Himnario Localmente',
                  ),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _restaurar,
                  icon: const Icon(Icons.restore),
                  label: const Text('Restaurar desde archivo'),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _irAlInicio,
                  child: const Text(
                    'Continuar sin descargar (requiere internet)',
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
