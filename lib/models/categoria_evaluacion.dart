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

  CategoriaEvaluacion copyWith({
    int? id,
    int? idRamo,
    String? nombre,
    double? porcentajeTotal,
    double? notaAprobacion,
    bool clearNotaAprobacion = false,
    String? averageType,
    String? customFormula,
    bool clearCustomFormula = false,
    bool? dropLowest,
    List<Evaluacion>? evaluaciones,
    int? droppedEvaluacionId,
  }) {
    return CategoriaEvaluacion(
      id: id ?? this.id,
      idRamo: idRamo ?? this.idRamo,
      nombre: nombre ?? this.nombre,
      porcentajeTotal: porcentajeTotal ?? this.porcentajeTotal,
      notaAprobacion:
          clearNotaAprobacion ? null : (notaAprobacion ?? this.notaAprobacion),
      averageType: averageType ?? this.averageType,
      customFormula:
          clearCustomFormula ? null : (customFormula ?? this.customFormula),
      dropLowest: dropLowest ?? this.dropLowest,
      evaluaciones: evaluaciones ?? this.evaluaciones,
      droppedEvaluacionId: droppedEvaluacionId ?? this.droppedEvaluacionId,
    );
  }

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
    final dropRaw = map['drop_lowest'];
    return CategoriaEvaluacion(
      id: (map['id'] as num?)?.toInt(),
      idRamo: (map['subject_id'] as num?)?.toInt() ?? 0,
      nombre: (map['name'] ?? '').toString(),
      porcentajeTotal: (map['total_weight'] is num)
          ? (map['total_weight'] as num).toDouble()
          : (double.tryParse(map['total_weight']?.toString() ?? '') ?? 0.0),
      notaAprobacion: map['min_passing_grade'] is num
          ? (map['min_passing_grade'] as num).toDouble()
          : double.tryParse(map['min_passing_grade']?.toString() ?? ''),
      averageType: (map['average_type'] ?? 'Aritmetico').toString(),
      customFormula: map['custom_formula']?.toString(),
      dropLowest: dropRaw == 1 || dropRaw == true,
    );
  }

  /// Rewrites variable tokens `e1`, `e2`, ... into `v1`, `v2`, ... so
  /// `math_expressions` does not interpret the leading `e` as Euler's constant.
  static String _rewriteIndexedVars(String formula) {
    return formula.replaceAllMapped(
      RegExp(r'(?<![A-Za-z0-9_])e(\d+)(?![A-Za-z0-9_])'),
      (m) => 'v${m.group(1)}',
    );
  }

  /// Validates whether [formula] parses cleanly and evaluates with sample values.
  /// Returns `null` if valid, or a user-facing error message if invalid.
  static String? validateCustomFormula(
    String formula, {
    int maxVariableCount = 12,
  }) {
    final trimmed = formula.trim();
    if (trimmed.isEmpty) {
      return 'La fórmula no puede estar vacía.';
    }
    try {
      final preprocessed = _preprocessFormula(trimmed);
      final normalized = _rewriteIndexedVars(preprocessed);
      final parser = GrammarParser();
      final exp = parser.parse(normalized);
      final cm = ContextModel();
      final varCount = maxVariableCount > 12 ? maxVariableCount : 12;
      for (int i = 0; i < varCount; i++) {
        cm.bindVariable(Variable('v${i + 1}'), Number(1.0));
      }
      // Also bind any higher eN variable referenced explicitly so validation succeeds.
      for (final match in RegExp(r'\bv(\d+)\b').allMatches(normalized)) {
        cm.bindVariable(Variable('v${match.group(1)}'), Number(1.0));
      }
      final val = RealEvaluator(cm).evaluate(exp).toDouble();
      if (!val.isFinite) {
        return 'La fórmula produce un resultado no finito (ej: división por cero).';
      }
      return null;
    } catch (_) {
      return 'Fórmula inválida. Revisa paréntesis, comas y operadores.';
    }
  }

  /// Mathematical average computation for this category.
  double? calcularPromedio() {
    droppedEvaluacionId = null;
    if (evaluaciones.isEmpty) return null;

    final gradedIndices = <int>[];
    for (int i = 0; i < evaluaciones.length; i++) {
      if (evaluaciones[i].nota != null) {
        gradedIndices.add(i);
      }
    }
    if (gradedIndices.isEmpty) return null;

    int? droppedIndex;
    if (dropLowest && gradedIndices.length > 1) {
      int worstIdx = gradedIndices.first;
      for (final idx in gradedIndices.skip(1)) {
        if (evaluaciones[idx].nota! < evaluaciones[worstIdx].nota!) {
          worstIdx = idx;
        }
      }
      droppedIndex = worstIdx;
      droppedEvaluacionId = evaluaciones[worstIdx].id;
    }

    final evsConNota = <Evaluacion>[
      for (final idx in gradedIndices)
        if (idx != droppedIndex) evaluaciones[idx],
    ];
    if (evsConNota.isEmpty) return null;

    if (averageType == 'Personalizada' &&
        customFormula != null &&
        customFormula!.trim().isNotEmpty) {
      try {
        final preprocessed = _preprocessFormula(customFormula!.trim());
        final normalized = _rewriteIndexedVars(preprocessed);
        final parser = GrammarParser();
        final exp = parser.parse(normalized);
        final cm = ContextModel();

        for (int i = 0; i < evaluaciones.length; i++) {
          final ev = evaluaciones[i];
          double val = 0.0;
          if (ev.nota != null && i != droppedIndex) {
            val = ev.nota!;
          }
          cm.bindVariable(Variable('v${i + 1}'), Number(val));
        }

        final result = RealEvaluator(cm).evaluate(exp).toDouble();
        return result.isFinite ? result : null;
      } catch (_) {
        return null;
      }
    } else if (averageType == 'Geometrico') {
      double sumLog = 0.0;
      for (final ev in evsConNota) {
        final g = ev.nota!;
        if (!g.isFinite || g < 0) return null;
        if (g == 0.0) return 0.0;
        sumLog += math.log(g);
      }
      final result = math.exp(sumLog / evsConNota.length);
      return result.isFinite ? result : null;
    } else {
      // Default Aritmetico
      final weightedEvs =
          evsConNota.where((e) => e.porcentajePeso != null && e.porcentajePeso! > 0).toList();
      if (weightedEvs.isNotEmpty) {
        final unweightedCount = evsConNota.length - weightedEvs.length;
        final explicitSum = weightedEvs.fold<double>(
          0.0,
          (sum, e) => sum + e.porcentajePeso!,
        );
        double fallbackWeight = 0.0;
        if (unweightedCount > 0) {
          final remaining = 100.0 - explicitSum;
          fallbackWeight = remaining > 0
              ? remaining / unweightedCount
              : explicitSum / weightedEvs.length;
        }

        double acumulado = 0.0;
        double pesos = 0.0;
        for (final ev in evsConNota) {
          final w = (ev.porcentajePeso != null && ev.porcentajePeso! > 0)
              ? ev.porcentajePeso!
              : fallbackWeight;
          if (w > 0) {
            acumulado += ev.nota! * (w / 100.0);
            pesos += w;
          }
        }
        if (pesos <= 0) return null;
        return acumulado / (pesos / 100.0);
      } else {
        double sum = 0.0;
        for (final ev in evsConNota) {
          sum += ev.nota!;
        }
        return sum / evsConNota.length;
      }
    }
  }

  static String _preprocessFormula(String input) {
    var str = input;
    var searchUpperBound = str.length;

    while (true) {
      final slice =
          searchUpperBound == str.length ? str : str.substring(0, searchUpperBound);
      final maxIdx = slice.lastIndexOf('max(');
      final minIdx = slice.lastIndexOf('min(');
      if (maxIdx == -1 && minIdx == -1) return str;

      final isMax = maxIdx > minIdx;
      final startIdx = isMax ? maxIdx : minIdx;

      // Ensure 'min(' / 'max(' is not a suffix of another identifier.
      if (startIdx > 0 && RegExp(r'[A-Za-z0-9_]').hasMatch(str[startIdx - 1])) {
        searchUpperBound = startIdx;
        continue;
      }

      int openCount = 0;
      final commas = <int>[];
      int? closeIdx;

      final contentStart = startIdx + 4;
      for (int i = contentStart; i < str.length; i++) {
        final ch = str[i];
        if (ch == '(') {
          openCount++;
        } else if (ch == ')') {
          if (openCount == 0) {
            closeIdx = i;
            break;
          }
          openCount--;
        } else if (ch == ',' && openCount == 0) {
          commas.add(i);
        }
      }

      if (commas.isEmpty || closeIdx == null) {
        searchUpperBound = startIdx;
        continue;
      }

      final args = <String>[];
      int argStart = contentStart;
      for (final cIdx in commas) {
        args.add(str.substring(argStart, cIdx).trim());
        argStart = cIdx + 1;
      }
      args.add(str.substring(argStart, closeIdx).trim());

      if (args.any((a) => a.isEmpty)) {
        searchUpperBound = startIdx;
        continue;
      }

      var replacement = args.first;
      for (int i = 1; i < args.length; i++) {
        final a = replacement;
        final b = args[i];
        replacement = isMax
            ? '(((($a)+($b))+abs(($a)-($b)))/2)'
            : '(((($a)+($b))-abs(($a)-($b)))/2)';
      }

      str = str.substring(0, startIdx) + replacement + str.substring(closeIdx + 1);
      searchUpperBound = str.length;
    }
  }
}
