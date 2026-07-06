class Evaluacion {
  int? id;
  int idCategoria;
  String nombre;
  double? porcentajePeso; // If null, means evenly distributed within the category
  double? nota;
  DateTime? fecha;

  Evaluacion({
    this.id,
    required this.idCategoria,
    required this.nombre,
    this.porcentajePeso,
    this.nota,
    this.fecha,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'category_id': idCategoria,
      'name': nombre,
      'specific_weight': porcentajePeso,
      'grade': nota,
      'date': fecha?.toIso8601String(),
    };
  }

  factory Evaluacion.fromMap(Map<String, dynamic> map) {
    return Evaluacion(
      id: map['id'],
      idCategoria: map['category_id'],
      nombre: map['name'],
      porcentajePeso: map['specific_weight'] != null ? (map['specific_weight'] as num).toDouble() : null,
      nota: map['grade'] != null ? (map['grade'] as num).toDouble() : null,
      fecha: map['date'] != null ? DateTime.parse(map['date']) : null,
    );
  }
}
