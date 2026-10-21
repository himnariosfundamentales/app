import 'dart:async';

import 'package:flutter/material.dart';
import '../data/catalogo.dart';
import '../models/himnario.dart';
import '../models/himno.dart';
import '../services/actualizacion_service.dart';
import '../services/download_service.dart';
import '../services/instalacion_web.dart';
import '../services/red_web.dart';
import '../services/respaldo_service.dart';
import '../services/terminos_service.dart';
import '../services/version_app_service.dart';
import 'ayuda_screen.dart';
import 'descarga_ui.dart';
import 'himnario_screen.dart';
import 'progreso_ui.dart';
import 'respaldo_ui.dart';
import 'resultado_busqueda.dart';
import 'visor_screen.dart';

/// Si un himnario se puede usar en este dispositivo y si ya funciona sin
/// internet.
class _Estado {
  final bool aceptado;
  final bool descargado;

  const _Estado(this.aceptado, this.descargado);
}

/// Pantalla principal: los himnarios, el buscador en todos ellos y el menú
/// general (respaldo, descargas, instalación y ayuda).
class InicioScreen extends StatefulWidget {
  const InicioScreen({super.key});

  @override
  State<InicioScreen> createState() => _InicioScreenState();
}

class _InicioScreenState extends State<InicioScreen> {
  final TextEditingController _busqueda = TextEditingController();
  List<HimnoEncontrado> _resultados = const [];
  Map<Himnario, _Estado> _estados = {};
  Map<Himnario, ActualizacionPendiente> _actualizaciones = {};

  @override
  void initState() {
    super.initState();
    // Con unos segundos de espera ya se cargó todo lo que la app usa al abrir
    // (la lista de assets se pide al mostrar las portadas).
    unawaited(
      Future<void>.delayed(
        const Duration(seconds: 5),
        RedWeb.guardarArchivosDeLaApp,
      ),
    );
    _cargarEstados();
    _revisarActualizaciones();
  }

  // Lo que se revisa por su cuenta (al abrir la app, o tras "Verificar
  // descargas") no abre su aviso encima de otro diálogo o pantalla: queda en
  // el botón de actualización.
  bool get _sinNadaEncima => ModalRoute.of(context)?.isCurrent ?? false;

  @override
  void dispose() {
    _busqueda.dispose();
    super.dispose();
  }

  Future<void> _cargarEstados() async {
    final Map<Himnario, _Estado> estados = {
      for (final Himnario himnario in Catalogo.todos)
        himnario: _Estado(
          await TerminosService.aceptados(himnario),
          await DownloadService.estaDescargado(himnario),
        ),
    };
    if (mounted) setState(() => _estados = estados);
  }

  static Map<Himnario, ActualizacionPendiente> _pendientes(
    Map<Himnario, Revision> revisiones,
  ) => {
    for (final MapEntry<Himnario, Revision> revision in revisiones.entries)
      if (revision.value.pendiente != null)
        revision.key: revision.value.pendiente!,
  };

  Future<void> _revisarActualizaciones() async {
    final Map<Himnario, Revision> revisiones =
        await ActualizacionService.revisarTodos();
    if (!mounted) return;
    setState(() => _actualizaciones = _pendientes(revisiones));
    if (_actualizaciones.isNotEmpty && _sinNadaEncima) {
      await _ofrecerActualizacion();
    }
  }

  void _buscar(String texto) =>
      setState(() => _resultados = Catalogo.buscar(texto));

  /// Abre el himnario, o directo el himno. Si el himnario pide términos y
  /// todavía no se aceptaron, primero se ofrece descargarlo.
  Future<void> _abrir(Himnario himnario, [Himno? himno]) async {
    if (!await TerminosService.aceptados(himnario)) {
      if (!mounted) return;
      final bool aceptado = await DescargaUi.descargar(context, himnario);
      await _cargarEstados();
      if (!aceptado) return;
    }
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => himno == null
            ? HimnarioScreen(himnario: himnario)
            : VisorScreen(himnario: himnario, himnoActual: himno),
      ),
    );
    // Adentro se pudo descargar otro himnario desde su buscador.
    await _cargarEstados();
  }

  Future<void> _descargar(Himnario himnario) async {
    await DescargaUi.descargar(context, himnario);
    await _cargarEstados();
  }

  PopupMenuItem<String> _opcion(String valor, IconData icono, String texto) {
    return PopupMenuItem<String>(
      value: valor,
      child: Row(
        children: [
          Icon(icono, size: 22),
          const SizedBox(width: 12),
          Text(texto),
        ],
      ),
    );
  }

  // Tras restaurar se revisa de nuevo: si el respaldo era más viejo que lo
  // publicado, ofrece bajar solo las hojas que cambiaron.
  Future<void> _restaurarRespaldo() async {
    final ResultadoRestauracion? resultado = await RespaldoUi.restaurar(
      context,
    );
    if (!mounted) return;
    // Aunque falle, pudo haber aceptado los términos de algún himnario.
    await _cargarEstados();
    if (resultado != null) await _revisarActualizaciones();
  }

  Future<void> _verificarDescargas() async {
    await _cargarEstados();
    final List<Himnario> sinDescargar = [
      for (final MapEntry<Himnario, _Estado> estado in _estados.entries)
        if (estado.value.aceptado && !estado.value.descargado) estado.key,
    ];
    if (sinDescargar.isNotEmpty && mounted) {
      final String nombres = sinDescargar.map((h) => h.nombre).join(', ');
      final bool? descargar = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Verificar descargas'),
          content: Text(
            'Todavía no se ha descargado para usar sin internet: $nombres. ¿Descargar ahora?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Ahora no'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Descargar'),
            ),
          ],
        ),
      );
      if (descargar == true) {
        for (final Himnario himnario in sinDescargar) {
          if (!mounted) return;
          await DescargaUi.descargar(context, himnario);
        }
        await _cargarEstados();
      }
    }

    if (!mounted) return;
    final ScaffoldMessengerState mensajes = ScaffoldMessenger.of(context);
    mensajes.showSnackBar(
      const SnackBar(content: Text('Verificando las descargas...')),
    );
    final Map<Himnario, Revision> revisiones =
        await ActualizacionService.revisarTodos();
    if (!mounted) return;
    mensajes.hideCurrentSnackBar();
    setState(() => _actualizaciones = _pendientes(revisiones));
    if (revisiones.values.any(
      (revision) => revision.estado == EstadoRevision.sinConexion,
    )) {
      mensajes.showSnackBar(
        const SnackBar(
          content: Text(
            'Sin conexión. Conéctate a internet para verificar las descargas.',
          ),
        ),
      );
    } else if (_actualizaciones.isEmpty) {
      mensajes.showSnackBar(
        const SnackBar(
          content: Text('Los himnarios descargados están completos y al día.'),
        ),
      );
    } else if (_sinNadaEncima) {
      await _ofrecerActualizacion();
    }
  }

  Future<void> _instalarApp() async {
    final ResultadoInstalacion resultado = await InstalacionWeb.instalar();
    if (!mounted) return;
    switch (resultado) {
      case ResultadoInstalacion.aceptada:
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Instalando la app...')));
      case ResultadoInstalacion.rechazada:
        break;
      case ResultadoInstalacion.noDisponible:
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Instalar APP'),
            content: const Text(
              'Este navegador no permite instalarla desde aquí, pero puedes hacerlo desde su menú:\n\n'
              '• Android (Chrome): menú ⋮ → "Instalar aplicación" o "Agregar a la pantalla principal". '
              'Si dice "Abrir en la app", ya está instalada.\n\n'
              '• iPhone o iPad (Safari): botón Compartir → "Agregar a pantalla de inicio".',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Entendido'),
              ),
            ],
          ),
        );
    }
  }

  String _describir(ActualizacionPendiente pendiente) {
    final int mejoradas = pendiente.mejoradas;
    final int faltantes = pendiente.faltantes;
    final List<String> partes = [
      if (mejoradas > 0)
        mejoradas == 1
            ? '1 hoja nueva o mejorada'
            : '$mejoradas hojas nuevas o mejoradas',
      if (faltantes > 0)
        faltantes == 1
            ? '1 hoja que falta en este dispositivo'
            : '$faltantes hojas que faltan en este dispositivo',
    ];
    final double mb = pendiente.bytes / 1e6;
    final String tamano = mb < 10
        ? mb.toStringAsFixed(1)
        : mb.round().toString();
    return '${pendiente.himnario.nombre}: ${partes.join(' y ')} (≈$tamano MB).';
  }

  Future<void> _ofrecerActualizacion() async {
    final List<ActualizacionPendiente> pendientes = _actualizaciones.values
        .toList();
    if (pendientes.isEmpty) return;
    final bool? aceptar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Actualización de himnarios'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final ActualizacionPendiente pendiente in pendientes)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_describir(pendiente)),
              ),
            const Text('¿Descargar ahora?'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Más tarde'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Descargar'),
          ),
        ],
      ),
    );
    if (aceptar == true && mounted) await _aplicarActualizaciones(pendientes);
  }

  Future<void> _aplicarActualizaciones(
    List<ActualizacionPendiente> pendientes,
  ) async {
    final ValueNotifier<int> hechas = ValueNotifier(0);
    final int total = pendientes.fold(
      0,
      (suma, pendiente) => suma + pendiente.hojas.length,
    );
    final DialogoProgreso progreso = DialogoProgreso.abrir(
      context,
      (context) => AlertDialog(
        title: const Text('Actualizando himnarios'),
        content: ValueListenableBuilder<int>(
          valueListenable: hechas,
          builder: (context, valor, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(value: valor / total),
              const SizedBox(height: 12),
              Text('$valor de $total hojas'),
            ],
          ),
        ),
      ),
    );

    int fallidas = 0;
    int anteriores = 0;
    for (final ActualizacionPendiente pendiente in pendientes) {
      final int base = anteriores;
      fallidas += await ActualizacionService.aplicar(
        pendiente,
        onProgreso: (valor, _) => hechas.value = base + valor,
      );
      anteriores += pendiente.hojas.length;
    }
    progreso.cerrar();
    hechas.dispose();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          fallidas == 0
              ? 'Himnarios actualizados.'
              : 'No se pudieron descargar $fallidas hojas. Revisa tu conexión e inténtalo de nuevo.',
        ),
      ),
    );

    // Si algo falló, se vuelve a revisar para dejar pendiente solo lo que faltó.
    final Map<Himnario, ActualizacionPendiente> restantes = fallidas == 0
        ? {}
        : _pendientes(await ActualizacionService.revisarTodos());
    if (mounted) setState(() => _actualizaciones = restantes);
  }

  @override
  Widget build(BuildContext context) {
    final int hojasPendientes = _actualizaciones.values.fold(
      0,
      (suma, pendiente) => suma + pendiente.hojas.length,
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Himnarios',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          if (hojasPendientes > 0)
            IconButton(
              tooltip: 'Descargar actualización',
              onPressed: _ofrecerActualizacion,
              icon: Badge(
                label: Text('$hojasPendientes'),
                child: const Icon(Icons.system_update_alt),
              ),
            ),
          PopupMenuButton<String>(
            tooltip: 'Más opciones',
            onSelected: (opcion) => switch (opcion) {
              'actualizar_app' => VersionAppService.actualizar(),
              'instalar' => _instalarApp(),
              'respaldo' => RespaldoUi.guardar(context),
              'restaurar' => _restaurarRespaldo(),
              'ayuda' => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AyudaScreen()),
              ),
              _ => _verificarDescargas(),
            },
            itemBuilder: (context) => [
              if (VersionAppService.versionNuevaDisponible)
                _opcion(
                  'actualizar_app',
                  Icons.system_update,
                  'Actualizar APP',
                ),
              if (!InstalacionWeb.estaInstalada)
                _opcion('instalar', Icons.install_mobile, 'Instalar APP'),
              _opcion('respaldo', Icons.save_alt, 'Guardar respaldo'),
              _opcion('restaurar', Icons.restore, 'Restaurar desde archivo'),
              _opcion('verificar', Icons.download_done, 'Verificar descargas'),
              _opcion('ayuda', Icons.help_outline, 'Ayuda'),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _busqueda,
              onChanged: _buscar,
              decoration: InputDecoration(
                labelText: 'Buscar en todos los himnarios',
                hintText: 'Título o número: 11, M11, G11',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10.0),
                ),
                suffixIcon: _busqueda.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _busqueda.clear();
                          _buscar('');
                        },
                      )
                    : null,
              ),
            ),
          ),
          Expanded(
            child: _busqueda.text.trim().isEmpty
                ? _construirHimnarios()
                : _construirResultados(),
          ),
        ],
      ),
    );
  }

  Widget _construirResultados() {
    if (_resultados.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No se encontró ningún himno.\nUn número solo busca en el Ministerio Musical; con M en Himnos Majestuosos, con G en Himnos de Gracia y con C en Celebremos su Gloria.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }
    return ListView.builder(
      itemCount: _resultados.length,
      itemBuilder: (context, index) {
        final HimnoEncontrado encontrado = _resultados[index];
        return ResultadoBusqueda(
          encontrado: encontrado,
          aceptado: _estados[encontrado.himnario]?.aceptado ?? false,
          onTap: () => _abrir(encontrado.himnario, encontrado.himno),
        );
      },
    );
  }

  Widget _construirHimnarios() {
    return LayoutBuilder(
      builder: (context, restricciones) {
        final int columnas = (restricciones.maxWidth / 220).floor().clamp(2, 6);
        final double ancho =
            (restricciones.maxWidth - 12 * (columnas + 1)) / columnas;
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columnas,
            crossAxisSpacing: 12,
            mainAxisSpacing: 16,
            // La portada tiene la proporción de una hoja carta; abajo van el
            // nombre y los botones.
            mainAxisExtent: ancho * 11 / 8.5 + 150,
          ),
          itemCount: Catalogo.todos.length,
          itemBuilder: (context, index) =>
              _construirTarjeta(Catalogo.todos[index]),
        );
      },
    );
  }

  Widget _construirTarjeta(Himnario himnario) {
    final _Estado? estado = _estados[himnario];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: 8.5 / 11,
          child: Material(
            elevation: 2,
            borderRadius: BorderRadius.circular(6),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => _abrir(himnario),
              child: Ink.image(
                image: AssetImage(himnario.portada),
                fit: BoxFit.cover,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          himnario.nombre,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const Spacer(),
        // Alto fijo: el botón principal queda a la misma altura en todas las
        // tarjetas, tengan uno o dos botones. En celulares y tablets cada
        // botón ocupa 48 de alto (lo mínimo para tocarlo con el dedo).
        SizedBox(
          height: 96,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (estado == null)
                const SizedBox.shrink()
              else if (!estado.aceptado)
                FilledButton.icon(
                  onPressed: () => _descargar(himnario),
                  icon: const Icon(Icons.download),
                  label: const Text('Descargar'),
                )
              else ...[
                FilledButton(
                  onPressed: () => _abrir(himnario),
                  child: const Text('Abrir'),
                ),
                if (estado.descargado)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.offline_pin, size: 18, color: Colors.green),
                        SizedBox(width: 4),
                        Text('Sin internet', style: TextStyle(fontSize: 13)),
                      ],
                    ),
                  )
                else
                  TextButton.icon(
                    onPressed: () => _descargar(himnario),
                    icon: const Icon(Icons.download, size: 18),
                    label: const Text('Descargar'),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
