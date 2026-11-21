import 'dart:math' as math;
import 'categoria_evaluacion.dart';

class Ramo {
  int? id;
  int idSemestre;
  String nombre;
  String tipoPromedio; // 'Aritmetico' or 'Geometrico'
  bool tieneGlobal;
  bool reemplazaPeorNota;
  double notaAprobacion;
  int orderIndex;
  int? color;
  List<CategoriaEvaluacion> categorias; // Transient

  Ramo({
    this.id,
    required this.idSemestre,
    required this.nombre,
    required this.tipoPromedio,
    required this.tieneGlobal,
    required this.reemplazaPeorNota,
    required this.notaAprobacion,
    this.orderIndex = 0,
    this.color,
    this.categorias = const [],
  });

  Ramo copyWith({
    int? id,
    int? idSemestre,
    String? nombre,
    String? tipoPromedio,
    bool? tieneGlobal,
    bool? reemplazaPeorNota,
    double? notaAprobacion,
    int? orderIndex,
    int? color,
    bool clearColor = false,
    List<CategoriaEvaluacion>? categorias,
  }) {
    return Ramo(
      id: id ?? this.id,
      idSemestre: idSemestre ?? this.idSemestre,
      nombre: nombre ?? this.nombre,
      tipoPromedio: tipoPromedio ?? this.tipoPromedio,
      tieneGlobal: tieneGlobal ?? this.tieneGlobal,
      reemplazaPeorNota: reemplazaPeorNota ?? this.reemplazaPeorNota,
      notaAprobacion: notaAprobacion ?? this.notaAprobacion,
      orderIndex: orderIndex ?? this.orderIndex,
      color: clearColor ? null : (color ?? this.color),
      categorias: categorias ?? this.categorias,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'semester_id': idSemestre,
      'name': nombre,
      'average_type': tipoPromedio,
      'has_global_exam': tieneGlobal ? 1 : 0,
      'global_exam_replaces_worst': reemplazaPeorNota ? 1 : 0,
      'min_passing_grade': notaAprobacion,
      'order_index': orderIndex,
      'color': color,
    };
  }

  factory Ramo.fromMap(Map<String, dynamic> map) {
    final globalRaw = map['has_global_exam'];
    final replaceRaw = map['global_exam_replaces_worst'];
    return Ramo(
      id: (map['id'] as num?)?.toInt(),
      idSemestre: (map['semester_id'] as num?)?.toInt() ?? 0,
      nombre: (map['name'] ?? '').toString(),
      tipoPromedio: (map['average_type'] ?? 'Aritmetico').toString(),
      tieneGlobal: globalRaw == 1 || globalRaw == true,
      reemplazaPeorNota: replaceRaw == 1 || replaceRaw == true,
      notaAprobacion: map['min_passing_grade'] is num
          ? (map['min_passing_grade'] as num).toDouble()
          : (double.tryParse(map['min_passing_grade']?.toString() ?? '') ?? 4.0),
      orderIndex: (map['order_index'] as num?)?.toInt() ?? 0,
      color: (map['color'] as num?)?.toInt(),
    );
  }

  double calcularNotaActual() {
    if (categorias.isEmpty) return 0.0;

    final isArithmetic =
        tipoPromedio == 'Aritmetico' || tipoPromedio == 'Aritmético';

    if (isArithmetic) {
      double notaPonderada = 0.0;
      double sumaPesos = 0.0;
      for (final cat in categorias) {
        final promCat = cat.calcularPromedio();
        if (promCat != null && cat.porcentajeTotal > 0) {
          notaPonderada += promCat * (cat.porcentajeTotal / 100.0);
          sumaPesos += cat.porcentajeTotal;
        }
      }
      if (sumaPesos <= 0) return 0.0;
      final normalized = notaPonderada / (sumaPesos / 100.0);
      if (!normalized.isFinite) return 0.0;
      return double.parse(normalized.toStringAsFixed(2));
    } else {
      // Geométrico: a 0.0 in any graded weighted category yields 0.0 instead of inflating the mean.
      double sumWeightedLog = 0.0;
      double sumaPesos = 0.0;
      bool hasZero = false;
      for (final cat in categorias) {
        final promCat = cat.calcularPromedio();
        if (promCat == null || cat.porcentajeTotal <= 0) continue;
        if (promCat < 0) return 0.0;
        sumaPesos += cat.porcentajeTotal;
        if (promCat == 0.0) {
          hasZero = true;
        } else {
          sumWeightedLog += (cat.porcentajeTotal / 100.0) * math.log(promCat);
        }
      }
      if (sumaPesos <= 0) return 0.0;
      if (hasZero) return 0.0;
      final normalized = math.exp(sumWeightedLog / (sumaPesos / 100.0));
      if (!normalized.isFinite) return 0.0;
      return double.parse(normalized.toStringAsFixed(2));
    }
  }
}
