import 'evaluacion.dart';

class CategoriaEvaluacion {
  int? id;
  int idRamo;
  String nombre;
  double porcentajeTotal;
  double? notaAprobacion;
  List<Evaluacion> evaluaciones; // Transient list of children

  CategoriaEvaluacion({
    this.id,
    required this.idRamo,
    required this.nombre,
    required this.porcentajeTotal,
    this.notaAprobacion,
    this.evaluaciones = const [],
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'subject_id': idRamo,
      'name': nombre,
      'total_weight': porcentajeTotal,
      'min_passing_grade': notaAprobacion,
    };
  }

  factory CategoriaEvaluacion.fromMap(Map<String, dynamic> map) {
    return CategoriaEvaluacion(
      id: map['id'],
      idRamo: map['subject_id'],
      nombre: map['name'],
      porcentajeTotal: (map['total_weight'] ?? 0).toDouble(),
      notaAprobacion: map['min_passing_grade'] != null ? (map['min_passing_grade'] as num).toDouble() : null,
    );
  }

  // Lógica matemática para esta categoría
  double? calcularPromedio() {
    if (evaluaciones.isEmpty) return null;
    
    // Si tienen pesos específicos, usar promedio ponderado
    bool usaPesosEspecificos = evaluaciones.any((e) => e.porcentajePeso != null);
    
    if (usaPesosEspecificos) {
      double acumulado = 0;
      double pesos = 0;
      for (var ev in evaluaciones) {
        if (ev.nota != null && ev.porcentajePeso != null) {
          acumulado += ev.nota! * (ev.porcentajePeso! / 100.0);
          pesos += ev.porcentajePeso!;
        }
      }
      if (pesos == 0) return null;
      return acumulado / (pesos / 100.0);
    } else {
      // Promedio simple de las que tienen nota
      var evsConNota = evaluaciones.where((e) => e.nota != null).toList();
      if (evsConNota.isEmpty) return null;
      double sum = 0;
      for (var ev in evsConNota) {
        sum += ev.nota!;
      }
      return sum / evsConNota.length;
    }
  }
}
