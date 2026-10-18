import 'package:flutter/material.dart';
import '../data/busqueda.dart';
import '../models/himnario.dart';
import '../models/himno.dart';
import 'visor_screen.dart';

enum OrdenHimnos { numero, nombre }

/// Lista de los himnos de un himnario, con su buscador.
class HimnarioScreen extends StatefulWidget {
  final Himnario himnario;

  const HimnarioScreen({super.key, required this.himnario});

  @override
  State<HimnarioScreen> createState() => _HimnarioScreenState();
}

class _HimnarioScreenState extends State<HimnarioScreen> {
  List<Himno> _himnosFiltrados = [];
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
    _himnosFiltrados = _himnosOrdenados;
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
      _himnosFiltrados = buscarEn(
        _himnario.quitarPrefijo(query),
        _himnosOrdenados,
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
                final himno = _himnosFiltrados[index];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: _himnario.color,
                    foregroundColor: Colors.white,
                    child: Text('${himno.numero}'),
                  ),
                  title: Text(himno.nombre),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => VisorScreen(
                          himnario: _himnario,
                          himnoActual: himno,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
