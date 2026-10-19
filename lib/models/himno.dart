import '../data/busqueda.dart';

class Himno {
  final String nombre;
  final int numero;

  Himno({required this.nombre, required this.numero});

  // Se calculan una vez: buscar y ordenar los recorren en cada tecla.
  late final String claveBusqueda = normalizar(nombre);
  late final String claveOrden = claveDeOrden(nombre);

  factory Himno.fromJson(Map<String, dynamic> json) {
    return Himno(
      nombre: json['nombre'] as String,
      numero: json['numero'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {'nombre': nombre, 'numero': numero};
  }
}
