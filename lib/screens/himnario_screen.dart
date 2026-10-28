import 'package:flutter/material.dart';
import '../data/catalogo.dart';
import '../models/himnario.dart';
import '../models/himno.dart';
import '../services/terminos_service.dart';
import 'descarga_ui.dart';
import 'resultado_busqueda.dart';
import 'visor_screen.dart';

enum OrdenHimnos { numero, nombre }

/// Lista de los himnos de un himnario, con su buscador. El buscador también
/// encuentra los de los otros himnarios, después de los de este.
class HimnarioScreen extends StatefulWidget {
  final Himnario himnario;

  const HimnarioScreen({super.key, required this.himnario});

  @override
  State<HimnarioScreen> createState() => _HimnarioScreenState();
}

class _HimnarioScreenState extends State<HimnarioScreen> {
  List<HimnoEncontrado> _himnosFiltrados = [];
  Set<Himnario> _aceptados = {};
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  OrdenHimnos _orden = OrdenHimnos.numero;

  Himnario get _himnario => widget.himnario;

  List<Himno> get _himnosOrdenados => _orden == OrdenHimnos.numero
      ? _himnario.himnosPorNumero
      : _himnario.himnosPorNombre;

  @override
  void initState() {
    super.initState();
    _filtrarHimnos('');
    _cargarAceptados();
  }

  Future<void> _cargarAceptados() async {
    final Set<Himnario> aceptados = await TerminosService.aceptadosDe(
      Catalogo.todos,
    );
    if (mounted) setState(() => _aceptados = aceptados);
  }

  Future<void> _abrir(HimnoEncontrado encontrado) async {
    if (encontrado.himnario != _himnario) {
      final bool aceptado = await DescargaUi.paraAbrir(
        context,
        encontrado.himnario,
      );
      await _cargarAceptados();
      if (!aceptado) return;
    }
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VisorScreen(
          himnario: encontrado.himnario,
          himnoActual: encontrado.himno,
        ),
      ),
    );
    // Desde el visor se pudo descargar otro himnario con su buscador.
    await _cargarAceptados();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _cambiarOrden(OrdenHimnos orden) {
    _orden = orden;
    _filtrarHimnos(_searchController.text);
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  void _filtrarHimnos(String query) {
    setState(() {
      _himnosFiltrados = query.trim().isEmpty
          ? [
              for (final Himno himno in _himnosOrdenados)
                HimnoEncontrado(_himnario, himno),
            ]
          : Catalogo.buscar(
              query,
              actual: _himnario,
              porNumero: _orden == OrdenHimnos.numero,
            );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _himnario.nombre,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Buscador
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _searchController,
              onChanged: _filtrarHimnos,
              decoration: InputDecoration(
                labelText: 'Buscar por número o título',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10.0),
                ),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _filtrarHimnos('');
                        },
                      )
                    : null,
              ),
            ),
          ),
          // Orden de la lista
          Padding(
            padding: const EdgeInsets.fromLTRB(12.0, 0, 12.0, 8.0),
            child: SegmentedButton<OrdenHimnos>(
              segments: const [
                ButtonSegment(
                  value: OrdenHimnos.numero,
                  icon: Icon(Icons.format_list_numbered),
                  label: Text('Número'),
                ),
                ButtonSegment(
                  value: OrdenHimnos.nombre,
                  icon: Icon(Icons.sort_by_alpha),
                  label: Text('Nombre'),
                ),
              ],
              selected: {_orden},
              onSelectionChanged: (seleccion) => _cambiarOrden(seleccion.first),
            ),
          ),
          // Lista de Himnos
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              itemCount: _himnosFiltrados.length,
              itemBuilder: (context, index) {
                final HimnoEncontrado encontrado = _himnosFiltrados[index];
                return ResultadoBusqueda(
                  encontrado: encontrado,
                  propio: encontrado.himnario == _himnario,
                  aceptado:
                      encontrado.himnario == _himnario ||
                      _aceptados.contains(encontrado.himnario),
                  conHimnario: _searchController.text.trim().isNotEmpty,
                  onTap: () => _abrir(encontrado),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
