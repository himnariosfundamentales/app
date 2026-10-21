import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/busqueda.dart';
import '../models/himnario.dart';
import '../models/himno.dart';
import '../services/download_service.dart';

class VisorScreen extends StatefulWidget {
  final Himnario himnario;
  final Himno himnoActual;

  const VisorScreen({
    super.key,
    required this.himnario,
    required this.himnoActual,
  });

  @override
  State<VisorScreen> createState() => _VisorScreenState();
}

class _VisorScreenState extends State<VisorScreen> {
  static const double _zoomMaximo = 4.0;
  static const String _keyAnchoHorizontal = 'ancho_hoja_horizontal';
  static const String _keyMultipagina = 'multipagina_horizontal';
  static const double _anchoToqueBarra = 36;

  static const Widget _indicadorCarga = Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularProgressIndicator(),
        SizedBox(height: 12),
        Text('Cargando himno...'),
      ],
    ),
  );

  late Himno _himnoActual;
  final TransformationController _transformacion = TransformationController();
  final SearchController _buscador = SearchController();
  bool? _busquedaPantallaCompleta;
  ui.PointerDeviceKind? _ultimoPuntero;

  // Las hojas del himnario: las páginas de cada himno y todas en orden, como
  // en el libro (cada una una vez, con null en las páginas en blanco del modo
  // libro). Null mientras se leen.
  Map<int, List<String>>? _paginasPorHimno;
  List<String?> _libro = const [];
  int _paginaActual = 1;
  bool _errorCarga = false;

  // Hojas ya decodificadas, por ruta. Se conservan las que se ven y las que
  // siguen, para pasar de hoja sin esperar; las demás se liberan.
  final Map<String, ui.Image> _imagenes = {};
  // Las que no se pudieron abrir: se muestra el error en lugar de
  // reintentarlas en bucle. Se vuelven a intentar al cambiar de página.
  final Set<String> _fallidas = {};
  bool _cargandoImagenes = false;

  final Set<int> _dedosEnPantalla = {};
  Offset? _inicioDeslizamiento;
  bool _huboVariosDedos = false;

  // Alto de la vista y de la página en la última distribución, para saber si
  // la página todavía se puede desplazar hacia arriba o hacia abajo.
  double _altoVista = 0;
  double _altoContenido = 0;
  bool _enBordeSuperior = true;
  bool _enBordeInferior = true;

  // En horizontal, fracción del ancho de la pantalla que ocupa la hoja. Null
  // hasta que el usuario la ajusta con las barras: la hoja se ajusta a lo alto
  // y se ve completa.
  double? _fraccionAncho;
  // Lo mismo para las dos hojas del modo libro, aparte de la hoja sola y sin
  // guardarse: al cambiar de página o de modo vuelven a verse completas.
  double? _fraccionAnchoLibro;
  // En horizontal se pueden ver las hojas de dos en dos, como un libro
  // abierto, aunque sean de himnos distintos.
  bool _multipagina = false;
  bool _conZoom = false;
  // Centro (x) de cada barra en la última distribución, para que arrastrar
  // una barra no cuente como deslizar a otra página.
  List<double> _barras = const [];

  @override
  void initState() {
    super.initState();
    _himnoActual = widget.himnoActual;
    _transformacion.addListener(_alCambiarZoom);
    HardwareKeyboard.instance.addHandler(_alTecla);
    SharedPreferences.getInstance().then((prefs) {
      if (!mounted) return;
      setState(() {
        _fraccionAncho = prefs.getDouble(_keyAnchoHorizontal);
        _multipagina = prefs.getBool(_keyMultipagina) ?? false;
      });
      _cargarImagenes();
    });
    _leerHojas();
  }

  Future<void> _leerHojas() async {
    try {
      final Map<int, List<String>> porHimno =
          await DownloadService.paginasPorHimno(widget.himnario);
      final List<String> todas = await DownloadService.todasLasRutas(
        widget.himnario,
      );
      if (!mounted) return;
      setState(() {
        _paginasPorHimno = porHimno;
        _libro = [
          for (final String ruta in todas) ...[
            if (widget.himnario.blancosAntes.contains(
              DownloadService.claveDe(widget.himnario, ruta),
            ))
              null,
            ruta,
          ],
        ];
      });
      _cargarImagenes();
    } catch (e) {
      debugPrint('No se pudo leer la lista de hojas: $e');
      if (mounted) setState(() => _errorCarga = true);
    }
  }

  // Las barras se ocultan con zoom: la hoja ampliada ya no coincide con ellas.
  void _alCambiarZoom() {
    if (_hayZoom != _conZoom) setState(() => _conZoom = _hayZoom);
  }

  double _anchoMinimo(Size vista, double aspecto) =>
      math.min(vista.width * 0.3, vista.height * aspecto);

  double _anchoHorizontal(Size vista, double aspecto) {
    final double completa = math.min(vista.width, vista.height * aspecto);
    final double? fraccion = _enLibro ? _fraccionAnchoLibro : _fraccionAncho;
    return (fraccion == null ? completa : fraccion * vista.width).clamp(
      _anchoMinimo(vista, aspecto),
      vista.width,
    );
  }

  // Las dos barras se mueven en espejo: la hoja (o las dos del modo libro)
  // crece o se achica centrada.
  void _ajustarAncho(Size vista, double aspecto, double cambio) {
    final double anterior = _anchoHorizontal(vista, aspecto);
    final double nuevo = (anterior + cambio).clamp(
      _anchoMinimo(vista, aspecto),
      vista.width,
    );
    if (nuevo == anterior) return;
    // Mantiene a la vista la misma parte de la hoja aunque cambie su alto.
    final double y =
        _transformacion.value.getTranslation().y * nuevo / anterior;
    final double maximo = math.max(0.0, nuevo / aspecto - vista.height);
    _transformacion.value = Matrix4.translationValues(
      0,
      y.clamp(-maximo, 0.0),
      0,
    );
    setState(() {
      if (_enLibro) {
        _fraccionAnchoLibro = nuevo / vista.width;
      } else {
        _fraccionAncho = nuevo / vista.width;
      }
    });
  }

  Future<void> _guardarAncho() async {
    final double? fraccion = _fraccionAncho;
    if (_enLibro || fraccion == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyAnchoHorizontal, fraccion);
  }

  Future<void> _cambiarMultipagina(bool valor) async {
    _transformacion.value = Matrix4.identity();
    setState(() {
      _multipagina = valor;
      _fraccionAnchoLibro = null;
    });
    _cargarImagenes();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyMultipagina, valor);
  }

  List<Himno> get _listaHimnos => widget.himnario.himnosPorNumero;

  int get _indiceActual =>
      _listaHimnos.indexWhere((h) => h.numero == _himnoActual.numero);

  List<String> get _rutasHimno =>
      _paginasPorHimno?[_himnoActual.numero] ?? const [];

  int get _totalPaginas => _rutasHimno.length;

  bool get _hayZoom => _transformacion.value.getMaxScaleOnAxis() > 1.01;

  bool get _enLibro =>
      _multipagina &&
      MediaQuery.orientationOf(context) == Orientation.landscape;

  String? get _rutaActual {
    final List<String> rutas = _rutasHimno;
    return rutas.isEmpty
        ? null
        : rutas[(_paginaActual - 1).clamp(0, rutas.length - 1)];
  }

  // En modo libro las hojas van de dos en dos como en el libro impreso, cada
  // una de su lado: las posiciones pares van a la izquierda. Las páginas en
  // blanco (ver Himnario.blancosAntes) acompañan a las que van solas, y si la
  // última queda a la izquierda, a su derecha va otra en blanco. Así los
  // himnos de dos hojas quedan juntos.
  String? _hojaEn(int posicion) =>
      posicion >= 0 && posicion < _libro.length ? _libro[posicion] : null;

  // Posición de la izquierda del par donde está [ruta]; -1 si no está.
  int _parDe(String? ruta) {
    final int i = ruta == null ? -1 : _libro.indexOf(ruta);
    return i < 0 ? -1 : i - i % 2;
  }

  // Lo que se ve, de izquierda a derecha: la página actual o, en modo libro,
  // su par. Null es una página en blanco.
  List<String?> get _rutasVisibles {
    final String? actual = _rutaActual;
    if (actual == null) return const [];
    final int par = _parDe(actual);
    if (!_enLibro || par < 0) return [actual];
    return [_hojaEn(par), _hojaEn(par + 1)];
  }

  // Las que se ven y, después, las que siguen: las otras páginas del himno,
  // de la más cercana a la más lejana, o en modo libro el par siguiente.
  List<String> get _hojasNecesarias {
    final String? actual = _rutaActual;
    if (actual == null) return const [];
    final int par = _parDe(actual);
    if (_enLibro && par >= 0) {
      return [
        for (int posicion = par; posicion < par + 4; posicion++)
          if (_hojaEn(posicion) case final String ruta) ruta,
      ];
    }
    final List<String> rutas = _rutasHimno;
    final int indice = rutas.indexOf(actual);
    return [
      for (int d = 0; d < rutas.length; d++)
        for (final int j in {indice + d, indice - d})
          if (j >= 0 && j < rutas.length) rutas[j],
    ];
  }

  // Cada página es una imagen de 2400 px de ancho, con resolución de sobra
  // para el zoom: el zoom solo la escala y no hay que volver a dibujar nada.
  // Se decodifican de una en una, primero las que se ven; tras cada una se
  // vuelve a ver qué hace falta, por si mientras tanto se cambió de página.
  Future<void> _cargarImagenes() async {
    if (_cargandoImagenes) return;
    _cargandoImagenes = true;
    try {
      while (mounted && !_errorCarga) {
        final List<String> necesarias = _hojasNecesarias;
        for (final String ruta in _imagenes.keys.toList()) {
          if (!necesarias.contains(ruta)) _imagenes.remove(ruta)!.dispose();
        }
        final String? siguiente = necesarias
            .where((r) => !_imagenes.containsKey(r) && !_fallidas.contains(r))
            .firstOrNull;
        if (siguiente == null) return;
        try {
          final ui.Image imagen = await decodeImageFromList(
            await DownloadService.obtenerPagina(siguiente),
          );
          if (!mounted) {
            imagen.dispose();
            return;
          }
          setState(() => _imagenes[siguiente] = imagen);
        } catch (e) {
          debugPrint('No se pudo abrir la hoja $siguiente: $e');
          if (mounted) setState(() => _fallidas.add(siguiente));
        }
      }
    } finally {
      _cargandoImagenes = false;
    }
  }

  // "24-1", "24-2"... en los himnos de varias hojas; "64" en los de una. Con
  // la letra del himnario si tiene ("M24-1").
  String _etiqueta(int numero, int pagina) {
    final String etiqueta = widget.himnario.etiqueta(numero);
    return (_paginasPorHimno?[numero]?.length ?? 1) > 1
        ? '$etiqueta-$pagina'
        : etiqueta;
  }

  // Una hoja se nombra con el himno actual si es una de sus páginas; si no,
  // con el himno con que empieza ("2-2_3-1" es la página 2 del himno 2).
  String _etiquetaDeHoja(String ruta) {
    final int pagina = _rutasHimno.indexOf(ruta) + 1;
    if (pagina > 0) return _etiqueta(_himnoActual.numero, pagina);
    final (int numero, int paginaDeEse) = DownloadService.lugarDe(
      widget.himnario,
      ruta,
    );
    return _etiqueta(numero, paginaDeEse);
  }

  // Lo que se ve: ["24-1"], o en modo libro ["24-1", "24-2"] o ["51", "52"]
  // (las páginas en blanco no se nombran).
  List<String> get _etiquetasVisibles {
    final List<String?> visibles = _rutasVisibles;
    if (visibles.isEmpty) {
      return [_etiqueta(_himnoActual.numero, _paginaActual)];
    }
    return [
      for (final String? ruta in visibles)
        if (ruta != null) _etiquetaDeHoja(ruta),
    ];
  }

  void _abrirHimno(Himno himno, {bool enUltimaPagina = false, int pagina = 1}) {
    _transformacion.value = Matrix4.identity();
    _altoContenido = 0;
    _fallidas.clear();
    setState(() {
      _himnoActual = himno;
      _errorCarga = false;
      _paginaActual = enUltimaPagina ? math.max(1, _rutasHimno.length) : pagina;
      _fraccionAnchoLibro = null;
    });
    _cargarImagenes();
  }

  void _reintentar() {
    _fallidas.clear();
    setState(() => _errorCarga = false);
    if (_paginasPorHimno == null) {
      _leerHojas();
    } else {
      _cargarImagenes();
    }
  }

  void _irAPagina(int numero) {
    _transformacion.value = Matrix4.identity();
    _fallidas.clear();
    setState(() {
      _paginaActual = numero;
      _fraccionAnchoLibro = null;
    });
    _cargarImagenes();
  }

  // Abre la hoja [ruta] como página actual, en el himno con que se nombra.
  void _irAHoja(String ruta) {
    final (int numero, int pagina) = DownloadService.lugarDe(
      widget.himnario,
      ruta,
    );
    if (numero == _himnoActual.numero) {
      _irAPagina(pagina);
      return;
    }
    final Himno? himno = _listaHimnos
        .where((h) => h.numero == numero)
        .firstOrNull;
    if (himno != null) _abrirHimno(himno, pagina: pagina);
  }

  // Como un libro: primero se pasan las páginas del himno y después se llega
  // al himno vecino. Al retroceder desde la primera página se abre el himno
  // anterior en su última página. En modo libro se pasa al par siguiente o al
  // anterior, por todas las hojas del himnario.
  void _avanzar(int direccion) {
    final int par = _parDe(_rutaActual);
    if (_enLibro && par >= 0) {
      final int destino = par + 2 * direccion;
      if (destino < 0 || destino >= _libro.length) return;
      // La de la izquierda del par, o la de la derecha si a la izquierda va
      // una página en blanco.
      _irAHoja((_hojaEn(destino) ?? _hojaEn(destino + 1))!);
      return;
    }
    final int pagina = _paginaActual + direccion;
    if (pagina >= 1 && pagina <= _totalPaginas) {
      _irAPagina(pagina);
      return;
    }
    final int nuevoIndice = _indiceActual + direccion;
    if (nuevoIndice >= 0 && nuevoIndice < _listaHimnos.length) {
      _abrirHimno(_listaHimnos[nuevoIndice], enUltimaPagina: direccion < 0);
    }
  }

  // Teclado y pedales para pasar páginas (se conectan como teclado Bluetooth,
  // en sus modos Re Pág/Av Pág, ←/→ o ↑/↓). Las flechas pasan de página
  // directamente, como un deslizamiento largo, aunque haya zoom.
  static final Map<LogicalKeyboardKey, int> _flechas = {
    LogicalKeyboardKey.arrowRight: 1,
    LogicalKeyboardKey.arrowDown: 1,
    LogicalKeyboardKey.arrowLeft: -1,
    LogicalKeyboardKey.arrowUp: -1,
  };
  // Re Pág/Av Pág primero recorren la hoja si es más alta que la pantalla.
  static final Map<LogicalKeyboardKey, int> _teclasPagina = {
    LogicalKeyboardKey.pageDown: 1,
    LogicalKeyboardKey.pageUp: -1,
  };

  // Algunos pedales mandan la misma tecla dos veces muy seguido y pasaban dos
  // páginas: después de cada movimiento se ignoran las teclas un momento.
  static const Duration _esperaEntreTeclas = Duration(seconds: 2);
  DateTime? _ultimaTecla;

  bool _alTecla(KeyEvent evento) {
    // Solo al pisar: mantener la tecla no pasa varias páginas seguidas.
    if (evento is! KeyDownEvent || !mounted) return false;
    final int? flecha = _flechas[evento.logicalKey];
    final int? pagina = _teclasPagina[evento.logicalKey];
    // Con la búsqueda (u otra pantalla) encima, las teclas son para ella.
    if ((flecha == null && pagina == null) ||
        _buscador.isOpen ||
        !(ModalRoute.isCurrentOf(context) ?? false)) {
      return false;
    }
    final DateTime ahora = DateTime.now();
    final DateTime? ultima = _ultimaTecla;
    if (ultima != null && ahora.difference(ultima) < _esperaEntreTeclas) {
      return true;
    }
    _ultimaTecla = ahora;
    if (flecha != null) {
      _avanzar(flecha);
    } else {
      _recorrerOPasar(pagina!);
    }
    return true;
  }

  // Si la hoja es más alta que la pantalla (en horizontal con las barras
  // abiertas, o con zoom), primero se recorre y solo desde el borde se pasa de
  // página, para no saltarse la parte de abajo. Cada paso repite un poco de lo
  // anterior para no perder el renglón.
  void _recorrerOPasar(int direccion) {
    final Matrix4 m = _transformacion.value;
    final double desplazado = -m.getTranslation().y;
    final double maximo = math.max(
      0.0,
      _altoContenido * m.getMaxScaleOnAxis() - _altoVista,
    );
    final double destino = (desplazado + direccion * _altoVista * 0.9).clamp(
      0.0,
      maximo,
    );
    if ((destino - desplazado).abs() > 1) {
      _transformacion.value = m.clone()
        ..setTranslationRaw(m.getTranslation().x, -destino, 0);
      return;
    }
    _avanzar(direccion);
  }

  // Deslizar pasa de página o de himno: hacia la izquierda o hacia arriba
  // avanza, hacia la derecha o hacia abajo retrocede. Se usan eventos de
  // puntero crudos porque el InteractiveViewer se queda con los gestos de
  // arrastre; solo cuenta con un dedo y sin zoom, para no chocar con el
  // pellizco ni con mover una página ampliada.
  void _alTocar(PointerDownEvent evento) {
    _dedosEnPantalla.add(evento.pointer);
    if (_dedosEnPantalla.length == 1) {
      if (_barras.any(
        (x) => (evento.localPosition.dx - x).abs() <= _anchoToqueBarra / 2,
      )) {
        _inicioDeslizamiento = null;
        return;
      }
      _inicioDeslizamiento = evento.position;
      _huboVariosDedos = false;
      final Matrix4 m = _transformacion.value;
      final double desplazado = -m.getTranslation().y;
      final double maximo = _altoContenido * m.getMaxScaleOnAxis() - _altoVista;
      _enBordeSuperior = desplazado <= 1;
      _enBordeInferior = desplazado >= maximo - 1;
    } else {
      _huboVariosDedos = true;
    }
  }

  void _alSoltar(PointerEvent evento) {
    _dedosEnPantalla.remove(evento.pointer);
    final Offset? inicio = _inicioDeslizamiento;
    if (_dedosEnPantalla.isNotEmpty || inicio == null) return;
    _inicioDeslizamiento = null;
    if (_huboVariosDedos || _hayZoom || evento is! PointerUpEvent) return;

    final Offset recorrido = evento.position - inicio;
    final Size pantalla = MediaQuery.sizeOf(context);
    if (recorrido.dx.abs() >= math.max(60.0, pantalla.width * 0.15) &&
        recorrido.dx.abs() > recorrido.dy.abs() * 2) {
      _avanzar(recorrido.dx < 0 ? 1 : -1);
    } else if (recorrido.dy.abs() >= math.max(60.0, pantalla.height * 0.12) &&
        recorrido.dy.abs() > recorrido.dx.abs() * 2) {
      // Si la página es más alta que la pantalla, primero se desplaza; solo
      // desde su borde (ya en el final o en el principio) cambia de elemento.
      if (recorrido.dy < 0 && _enBordeInferior) _avanzar(1);
      if (recorrido.dy > 0 && _enBordeSuperior) _avanzar(-1);
    }
  }

  List<Himno> _sugerencias(String texto) {
    if (texto.trim().isEmpty) return const [];
    return buscarEn(widget.himnario.quitarPrefijo(texto), _listaHimnos);
  }

  void _irAlHimnoBuscado(Himno himno) {
    _buscador.closeView('');
    FocusManager.instance.primaryFocus?.unfocus();
    _abrirHimno(himno);
  }

  // Chrome en tablets grandes abre los sitios en modo escritorio, así que
  // Flutter cree que es una PC y abre la búsqueda como panel. Ese panel se
  // cierra cuando el teclado en pantalla cambia el tamaño de la ventana, antes
  // de que llegue el toque en la sugerencia. Por eso se decide según con qué
  // se tocó la barra: dedo o lápiz, pantalla completa; mouse, panel.
  void _abrirBusqueda(SearchController controller) {
    if (controller.isOpen) return;
    final ui.PointerDeviceKind? puntero = _ultimoPuntero;
    final bool? pantallaCompleta = puntero == null
        ? null
        : puntero != ui.PointerDeviceKind.mouse;
    if (pantallaCompleta == _busquedaPantallaCompleta) {
      controller.openView();
      return;
    }
    setState(() => _busquedaPantallaCompleta = pantallaCompleta);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !controller.isOpen) controller.openView();
    });
  }

  Widget _construirBuscador() {
    return SearchAnchor(
      searchController: _buscador,
      isFullScreen: _busquedaPantallaCompleta,
      viewHintText: 'Buscar por número o título',
      viewBackgroundColor: Colors.white,
      viewSurfaceTintColor: Colors.transparent,
      viewOnSubmitted: (texto) {
        final List<Himno> resultados = _sugerencias(texto);
        if (resultados.isNotEmpty) _irAlHimnoBuscado(resultados.first);
      },
      builder: (context, controller) => Listener(
        onPointerDown: (evento) => _ultimoPuntero = evento.kind,
        child: SearchBar(
          controller: controller,
          hintText: 'Buscar',
          leading: const Icon(Icons.search),
          elevation: const WidgetStatePropertyAll(0),
          backgroundColor: const WidgetStatePropertyAll(Colors.white),
          constraints: const BoxConstraints(maxWidth: 110, minHeight: 40),
          side: WidgetStatePropertyAll(
            BorderSide(color: Theme.of(context).colorScheme.outline),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onTap: () => _abrirBusqueda(controller),
          onChanged: (_) => _abrirBusqueda(controller),
        ),
      ),
      suggestionsBuilder: (context, controller) =>
          _sugerencias(controller.text).map(
            (himno) => ListTile(
              leading: CircleAvatar(
                backgroundColor: widget.himnario.color,
                foregroundColor: Colors.white,
                child: Text('${himno.numero}'),
              ),
              title: Text(himno.nombre),
              onTap: () => _irAlHimnoBuscado(himno),
            ),
          ),
    );
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_alTecla);
    _buscador.dispose();
    _transformacion.dispose();
    for (final ui.Image imagen in _imagenes.values) {
      imagen.dispose();
    }
    _imagenes.clear();
    super.dispose();
  }

  Widget _construirError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              'No se pudo abrir el himno #${widget.himnario.etiqueta(_himnoActual.numero)}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Revisa tu conexión a internet o descarga el himnario para usarlo sin conexión.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _reintentar,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  // [hojas] van lado a lado: una, o dos en modo libro. Null es una página en
  // blanco.
  Widget _construirPagina(List<ui.Image?> hojas) {
    return LayoutBuilder(
      builder: (context, restricciones) {
        final Size vista = restricciones.biggest;
        final ui.Image muestra = hojas.nonNulls.first;
        final double aspecto = hojas.length * muestra.width / muestra.height;
        // En horizontal la hoja a todo lo ancho no cabe a lo alto; por eso se
        // angosta, con barras a los lados para ajustarla. En modo libro las
        // dos hojas son un solo lienzo, con una barra a cada lado.
        final bool horizontal = vista.width > vista.height;
        final double ancho = horizontal
            ? _anchoHorizontal(vista, aspecto)
            : vista.width;
        final double altoPagina = ancho / aspecto;
        _altoVista = vista.height;
        _altoContenido = math.max(vista.height, altoPagina);

        final bool conBarras = horizontal && !_conZoom;
        final double margen = (vista.width - ancho) / 2;
        final List<(int, double)> barras = [
          for (final (int lado, double borde) in [
            (-1, margen),
            (1, vista.width - margen),
          ])
            (
              lado,
              (borde - _anchoToqueBarra / 2).clamp(
                0.0,
                vista.width - _anchoToqueBarra,
              ),
            ),
        ];
        _barras = conBarras
            ? [
                for (final (_, izquierda) in barras)
                  izquierda + _anchoToqueBarra / 2,
              ]
            : const [];

        final Widget visor = InteractiveViewer(
          transformationController: _transformacion,
          constrained: false,
          minScale: 1.0,
          maxScale: _zoomMaximo,
          child: SizedBox(
            width: vista.width,
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: vista.height),
              child: Center(
                child: SizedBox(
                  width: ancho,
                  height: altoPagina,
                  child: Row(
                    children: [
                      for (final ui.Image? hoja in hojas)
                        Expanded(
                          child: hoja == null
                              ? const ColoredBox(color: Colors.white)
                              : RawImage(
                                  image: hoja,
                                  fit: BoxFit.fill,
                                  filterQuality: FilterQuality.medium,
                                ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        // Siempre dentro del Stack, aunque no haya barras: si el visor cambiara
        // de lugar en el árbol al ocultarlas, Flutter lo recrearía y cortaría
        // el pellizco justo cuando empieza el zoom.
        return Stack(
          children: [
            visor,
            if (conBarras)
              for (final (int lado, double izquierda) in barras)
                Positioned(
                  left: izquierda,
                  top: 0,
                  bottom: 0,
                  width: _anchoToqueBarra,
                  child: _BarraAncho(
                    onArrastre: (dx) =>
                        _ajustarAncho(vista, aspecto, lado * dx * 2),
                    onFin: _guardarAncho,
                  ),
                ),
          ],
        );
      },
    );
  }

  Widget _construirCuerpo() {
    if (_errorCarga) return _construirError();
    final List<String?> visibles = _rutasVisibles;
    if (_paginasPorHimno != null && visibles.isEmpty) {
      return _construirError(); // un himno sin hojas
    }
    if (visibles.any(_fallidas.contains)) return _construirError();
    if (visibles.isEmpty ||
        visibles.any((ruta) => ruta != null && !_imagenes.containsKey(ruta))) {
      // Por ejemplo al girar la pantalla en modo libro: ahora se ven otras.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _cargarImagenes();
      });
      return _indicadorCarga;
    }
    return _construirPagina([
      for (final String? ruta in visibles)
        ruta == null ? null : _imagenes[ruta],
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final int par = _parDe(_rutaActual);
    final bool libro = _enLibro && par >= 0;
    final int indice = _indiceActual;
    final List<String?> visibles = _rutasVisibles;
    final bool hayAnterior = libro ? par > 0 : indice > 0 || _paginaActual > 1;
    final bool haySiguiente = libro
        ? par + 2 < _libro.length
        : (indice >= 0 && indice < _listaHimnos.length - 1) ||
              _paginaActual < _totalPaginas;
    final bool mostrarPaginas = _totalPaginas > 1;
    final bool mostrarMultipagina =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final List<String> etiquetas = _etiquetasVisibles;

    return Scaffold(
      // --- TOP BAR ---
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          libro
              ? 'Himno: ${etiquetas.map((e) => '#$e').join(' y ')}'
              : 'Himno #${etiquetas.first}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: _construirBuscador(),
          ),
        ],
      ),

      // --- CENTRO (VISOR) ---
      body: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _alTocar,
        onPointerUp: _alSoltar,
        onPointerCancel: _alSoltar,
        child: _construirCuerpo(),
      ),

      // --- BOTTOM BAR ---
      bottomNavigationBar: Container(
        color: Theme.of(context).cardColor,
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // BARRA HORIZONTAL DE PÁGINAS (Solo si el himno tiene más de 1 página)
            if (mostrarPaginas)
              SizedBox(
                height: 40,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12.0),
                  itemCount: _totalPaginas,
                  itemBuilder: (context, index) {
                    int numPagina = index + 1;
                    bool esSeleccionada = visibles.contains(_rutasHimno[index]);
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4.0),
                      child: ChoiceChip(
                        label: Text(_etiqueta(_himnoActual.numero, numPagina)),
                        selected: esSeleccionada,
                        onSelected: (bool selected) {
                          if (selected) _irAPagina(numPagina);
                        },
                      ),
                    );
                  },
                ),
              ),

            if (mostrarPaginas) const SizedBox(height: 6),

            // NAVEGACIÓN << # >> (páginas y himnos, como un libro), centrada
            // entre dos espacios iguales; en el derecho va "Multipágina".
            Row(
              children: [
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios),
                  onPressed: hayAnterior ? () => _avanzar(-1) : null,
                  tooltip: 'Anterior',
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  child: Text(
                    etiquetas.join(' y '),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_forward_ios),
                  onPressed: haySiguiente ? () => _avanzar(1) : null,
                  tooltip: 'Siguiente',
                ),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: mostrarMultipagina
                        ? Padding(
                            padding: const EdgeInsets.only(right: 16),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () => _cambiarMultipagina(!_multipagina),
                              child: Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Checkbox(
                                      value: _multipagina,
                                      onChanged: (valor) =>
                                          _cambiarMultipagina(valor ?? false),
                                    ),
                                    const Text('Multipágina'),
                                  ],
                                ),
                              ),
                            ),
                          )
                        : null,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Barra lateral para ajustar el ancho de la hoja en horizontal: una línea
/// fina con una agarradera en el centro, y una zona de toque más ancha.
class _BarraAncho extends StatelessWidget {
  final void Function(double dx) onArrastre;
  final VoidCallback onFin;

  const _BarraAncho({required this.onArrastre, required this.onFin});

  @override
  Widget build(BuildContext context) {
    final Color color = Theme.of(context).colorScheme.outline;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (detalles) => onArrastre(detalles.delta.dx),
        onHorizontalDragEnd: (_) => onFin(),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(width: 1.5, color: color.withValues(alpha: 0.35)),
            Container(
              width: 8,
              height: 64,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
