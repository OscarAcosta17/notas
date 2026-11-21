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

  Evaluacion copyWith({
    int? id,
    int? idCategoria,
    String? nombre,
    double? porcentajePeso,
    bool clearPorcentajePeso = false,
    double? nota,
    bool clearNota = false,
    DateTime? fecha,
    bool clearFecha = false,
  }) {
    return Evaluacion(
      id: id ?? this.id,
      idCategoria: idCategoria ?? this.idCategoria,
      nombre: nombre ?? this.nombre,
      porcentajePeso:
          clearPorcentajePeso ? null : (porcentajePeso ?? this.porcentajePeso),
      nota: clearNota ? null : (nota ?? this.nota),
      fecha: clearFecha ? null : (fecha ?? this.fecha),
    );
  }

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
    final rawDate = map['date']?.toString().trim();
    return Evaluacion(
      id: (map['id'] as num?)?.toInt(),
      idCategoria: (map['category_id'] as num?)?.toInt() ?? 0,
      nombre: (map['name'] ?? '').toString(),
      porcentajePeso: map['specific_weight'] is num
          ? (map['specific_weight'] as num).toDouble()
          : double.tryParse(map['specific_weight']?.toString() ?? ''),
      nota: map['grade'] is num
          ? (map['grade'] as num).toDouble()
          : double.tryParse(map['grade']?.toString() ?? ''),
      fecha: (rawDate != null && rawDate.isNotEmpty)
          ? DateTime.tryParse(rawDate)
          : null,
    );
  }
}
