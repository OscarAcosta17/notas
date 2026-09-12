import 'dart:math' as math;
import 'package:math_expressions/math_expressions.dart';
import 'evaluacion.dart';

class CategoriaEvaluacion {
  int? id;
  int idRamo;
  String nombre;
  double porcentajeTotal;
  double? notaAprobacion;
  String averageType;
  String? customFormula;
  bool dropLowest;
  List<Evaluacion> evaluaciones; // Transient list of children
  int? droppedEvaluacionId; // Transient property for UI

  CategoriaEvaluacion({
    this.id,
    required this.idRamo,
    required this.nombre,
    required this.porcentajeTotal,
    this.notaAprobacion,
    this.averageType = 'Aritmetico',
    this.customFormula,
    this.dropLowest = false,
    this.evaluaciones = const [],
    this.droppedEvaluacionId,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'subject_id': idRamo,
      'name': nombre,
      'total_weight': porcentajeTotal,
      'min_passing_grade': notaAprobacion,
      'average_type': averageType,
      'custom_formula': customFormula,
      'drop_lowest': dropLowest ? 1 : 0,
    };
  }

  factory CategoriaEvaluacion.fromMap(Map<String, dynamic> map) {
    return CategoriaEvaluacion(
      id: map['id'],
      idRamo: map['subject_id'],
      nombre: map['name'],
      porcentajeTotal: (map['total_weight'] ?? 0).toDouble(),
      notaAprobacion: map['min_passing_grade'] != null ? (map['min_passing_grade'] as num).toDouble() : null,
      averageType: map['average_type'] ?? 'Aritmetico',
      customFormula: map['custom_formula'],
      dropLowest: map['drop_lowest'] == 1,
    );
  }

  // Lógica matemática para esta categoría
  double? calcularPromedio() {
    droppedEvaluacionId = null;
    if (evaluaciones.isEmpty) return null;

    var evsConNota = evaluaciones.where((e) => e.nota != null).toList();
    if (evsConNota.isEmpty) return null;

    if (dropLowest && evsConNota.length > 1) {
      Evaluacion peorEvaluacion = evsConNota.reduce((a, b) => a.nota! < b.nota! ? a : b);
      droppedEvaluacionId = peorEvaluacion.id;
      evsConNota.remove(peorEvaluacion);
    }

    if (averageType == 'Personalizada' && customFormula != null && customFormula!.isNotEmpty) {
      try {
        String preprocessed = _preprocessFormula(customFormula!);
        Parser p = Parser();
        Expression exp = p.parse(preprocessed);
        ContextModel cm = ContextModel();

        // Evaluate using original indices. User writes e1, e2, e3 based on creation order.
        // Even if one is dropped, we should probably set its variable to 0 or remove it?
        // Wait, if it's custom formula, maybe drop lowest is weird? We'll just bind the variables.
        // We will bind e1, e2, ... to the *actual* evaluated grades.
        for (int i = 0; i < evaluaciones.length; i++) {
          final ev = evaluaciones[i];
          double val = 0.0;
          if (ev.nota != null && ev.id != droppedEvaluacionId) {
            val = ev.nota!;
          }
          cm.bindVariable(Variable('e\${i + 1}'), Number(val));
        }

        return exp.evaluate(EvaluationType.REAL, cm);
      } catch (e) {
        return null; // Error in formula
      }
    } else if (averageType == 'Geometrico') {
      double producto = 1.0;
      for (var ev in evsConNota) {
        producto *= ev.nota!;
      }
      return math.pow(producto, 1 / evsConNota.length).toDouble();
    } else {
      // Default Aritmetico
      bool usaPesosEspecificos = evsConNota.any((e) => e.porcentajePeso != null);
      if (usaPesosEspecificos) {
        double acumulado = 0;
        double pesos = 0;
        for (var ev in evsConNota) {
          if (ev.porcentajePeso != null) {
            acumulado += ev.nota! * (ev.porcentajePeso! / 100.0);
            pesos += ev.porcentajePeso!;
          }
        }
        if (pesos == 0) return null;
        return acumulado / (pesos / 100.0);
      } else {
        double sum = 0;
        for (var ev in evsConNota) {
          sum += ev.nota!;
        }
        return sum / evsConNota.length;
      }
    }
  }

  String _preprocessFormula(String str) {
    int maxIdx = str.lastIndexOf('max(');
    int minIdx = str.lastIndexOf('min(');
    if (maxIdx == -1 && minIdx == -1) return str;
    
    bool isMax = maxIdx > minIdx;
    int startIdx = isMax ? maxIdx : minIdx;
    
    int openCount = 0;
    int? commaIdx;
    int? closeIdx;
    
    int contentStart = startIdx + 4; // 'max(' or 'min('
    for (int i = contentStart; i < str.length; i++) {
      if (str[i] == '(') openCount++;
      else if (str[i] == ')') {
        if (openCount == 0) {
          closeIdx = i;
          break;
        }
        openCount--;
      } else if (str[i] == ',' && openCount == 0) {
        commaIdx = i;
      }
    }
    
    if (commaIdx != null && closeIdx != null) {
      String A = str.substring(contentStart, commaIdx);
      String B = str.substring(commaIdx + 1, closeIdx);
      
      String replacement;
      if (isMax) {
        replacement = '((($A)+($B))+abs(($A)-($B)))/2';
      } else {
        replacement = '((($A)+($B))-abs(($A)-($B)))/2';
      }
      
      String newStr = str.substring(0, startIdx) + replacement + str.substring(closeIdx + 1);
      return _preprocessFormula(newStr);
    }
    
    return str;
  }
}
