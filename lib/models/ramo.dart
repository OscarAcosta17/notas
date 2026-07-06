import 'dart:math';
import 'categoria_evaluacion.dart';

class Ramo {
  int? id;
  int idSemestre;
  String nombre;
  String tipoPromedio; // 'Aritmetico' or 'Geometrico'
  bool tieneGlobal;
  bool reemplazaPeorNota; // true = replaces worst evaluation in a specific category (usually not supported with new generic categories, keeping for legacy compatibility or we just ignore it if it's too complex. Actually, the user asked for generic categories, so we'll adapt global logic: if a category is named "Global", it replaces worst category or we just treat it as a standard category with 1 evaluation).
  double notaAprobacion;
  List<CategoriaEvaluacion> categorias; // Transient

  Ramo({
    this.id,
    required this.idSemestre,
    required this.nombre,
    required this.tipoPromedio,
    required this.tieneGlobal,
    required this.reemplazaPeorNota,
    required this.notaAprobacion,
    this.categorias = const [],
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'semester_id': idSemestre,
      'name': nombre,
      'average_type': tipoPromedio,
      'has_global_exam': tieneGlobal ? 1 : 0,
      'global_exam_replaces_worst': reemplazaPeorNota ? 1 : 0,
      'min_passing_grade': notaAprobacion,
    };
  }

  factory Ramo.fromMap(Map<String, dynamic> map) {
    return Ramo(
      id: map['id'],
      idSemestre: map['semester_id'],
      nombre: map['name'],
      tipoPromedio: map['average_type'],
      tieneGlobal: map['has_global_exam'] == 1,
      reemplazaPeorNota: map['global_exam_replaces_worst'] == 1,
      notaAprobacion: (map['min_passing_grade'] ?? 4.0).toDouble(),
    );
  }

  // --- LÓGICA MATEMÁTICA ---
  
  double calcularNotaActual() {
    if (categorias.isEmpty) return 0.0;

    double notaPonderada = 0.0;
    double sumaPesos = 0.0;

    if (tipoPromedio == 'Aritmetico' || tipoPromedio == 'Aritmético') {
      for (var cat in categorias) {
        double? promCat = cat.calcularPromedio();
        if (promCat != null) {
          notaPonderada += promCat * (cat.porcentajeTotal / 100.0);
          sumaPesos += cat.porcentajeTotal;
        }
      }
      if (sumaPesos == 0) return 0.0;
      notaPonderada = (notaPonderada / (sumaPesos / 100.0)); // Normalize to 100% of graded categories
    } else {
      // Geométrico
      double producto = 1.0;
      for (var cat in categorias) {
        double? promCat = cat.calcularPromedio();
        if (promCat != null && promCat > 0) {
          producto *= pow(promCat, cat.porcentajeTotal / 100.0);
          sumaPesos += cat.porcentajeTotal;
        }
      }
      if (sumaPesos == 0) return 0.0;
      notaPonderada = pow(producto, 1 / (sumaPesos / 100.0)).toDouble();
    }

    return double.parse(notaPonderada.toStringAsFixed(2));
  }

  double calcularNotaNecesaria() {
    // Cálculo simplificado: si falta nota en una categoría, 
    // asumimos que el peso faltante se necesita para llegar a notaAprobacion.
    
    double notaAcumulada = 0.0;
    double pesoPendienteTotal = 0.0;

    for (var cat in categorias) {
      double? promCat = cat.calcularPromedio();
      if (promCat != null) {
        notaAcumulada += promCat * (cat.porcentajeTotal / 100.0);
      } else {
        pesoPendienteTotal += cat.porcentajeTotal;
      }
    }

    if (pesoPendienteTotal == 0.0) return 0.0; // Ya se evaluó todo

    if (tipoPromedio == 'Aritmetico' || tipoPromedio == 'Aritmético') {
      double requerida = (notaAprobacion - notaAcumulada) / (pesoPendienteTotal / 100.0);
      return requerida > 0 ? double.parse(requerida.toStringAsFixed(2)) : 0.0;
    } else {
      // Geometrico
      double productoAcumulado = 1.0;
      for (var cat in categorias) {
        double? promCat = cat.calcularPromedio();
        if (promCat != null && promCat > 0) {
          productoAcumulado *= pow(promCat, cat.porcentajeTotal / 100.0);
        }
      }
      if (productoAcumulado == 0.0) return 0.0;
      double requerida = pow((notaAprobacion / productoAcumulado), 1 / (pesoPendienteTotal / 100.0)).toDouble();
      return requerida > 0 ? double.parse(requerida.toStringAsFixed(2)) : 0.0;
    }
  }
}
