import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import '../models/evaluacion.dart';
import '../services/database_helper.dart';

final evaluacionProvider = NotifierProvider.family<EvaluacionNotifier, List<Evaluacion>, int>((int arg) {
  final notifier = EvaluacionNotifier();
  notifier.arg = arg;
  return notifier;
});

class EvaluacionNotifier extends Notifier<List<Evaluacion>> {
  late int arg;

  @override
  List<Evaluacion> build() {
    cargarEvaluaciones();
    return [];
  }

  Future<void> cargarEvaluaciones() async {
    try {
      final data = await DatabaseHelper.instance.queryEvaluationsByCategory(arg);
      state = data.map((e) => Evaluacion.fromMap(e)).toList();
    } catch (e) {
      debugPrint("Error al cargar evaluaciones: \$e");
    }
  }

  Future<void> agregarEvaluacion(Evaluacion evaluacion) async {
    try {
      await DatabaseHelper.instance.insertEvaluation(evaluacion.toMap());
      await cargarEvaluaciones();
    } catch (e) {
      debugPrint("Error al agregar evaluacion: \$e");
    }
  }

  Future<void> actualizarEvaluacion(Evaluacion evaluacion) async {
    try {
      await DatabaseHelper.instance.updateEvaluation(evaluacion.toMap());
      await cargarEvaluaciones();
    } catch (e) {
      debugPrint("Error al actualizar evaluacion: \$e");
    }
  }

  Future<void> eliminarEvaluacion(int id) async {
    try {
      await DatabaseHelper.instance.deleteEvaluation(id);
      await cargarEvaluaciones();
    } catch (e) {
      debugPrint("Error al eliminar evaluacion: \$e");
    }
  }
}
