import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import '../models/categoria_evaluacion.dart';
import '../models/evaluacion.dart';
import '../services/database_helper.dart';

final categoriaProvider = NotifierProvider.family<CategoriaNotifier, List<CategoriaEvaluacion>, int>((int arg) {
  final notifier = CategoriaNotifier();
  notifier.arg = arg;
  return notifier;
});

class CategoriaNotifier extends Notifier<List<CategoriaEvaluacion>> {
  late int arg; // subjectId

  @override
  List<CategoriaEvaluacion> build() {
    cargarCategorias();
    return [];
  }

  Future<void> cargarCategorias() async {
    try {
      final data = await DatabaseHelper.instance.queryCategoriesBySubject(arg);
      List<CategoriaEvaluacion> cats = [];
      for (var catMap in data) {
        var cat = CategoriaEvaluacion.fromMap(catMap);
        final evsData = await DatabaseHelper.instance.queryEvaluationsByCategory(cat.id!);
        cat.evaluaciones = evsData.map((e) => Evaluacion.fromMap(e)).toList();
        cats.add(cat);
      }
      state = cats;
    } catch (e) {
      debugPrint("Error al cargar categorias: $e");
    }
  }

  Future<void> agregarCategoria(CategoriaEvaluacion categoria) async {
    try {
      await DatabaseHelper.instance.insertCategory(categoria.toMap());
      await cargarCategorias();
    } catch (e) {
      debugPrint("Error al agregar categoria: $e");
    }
  }

  Future<void> actualizarCategoria(CategoriaEvaluacion categoria) async {
    try {
      await DatabaseHelper.instance.updateCategory(categoria.toMap());
      await cargarCategorias();
    } catch (e) {
      debugPrint("Error al actualizar categoria: $e");
    }
  }

  Future<void> eliminarCategoria(int id) async {
    try {
      await DatabaseHelper.instance.deleteCategory(id);
      await cargarCategorias();
    } catch (e) {
      debugPrint("Error al eliminar categoria: $e");
    }
  }

  // --- Manejo de Evaluaciones ---
  Future<void> agregarEvaluacion(Evaluacion evaluacion) async {
    try {
      await DatabaseHelper.instance.insertEvaluation(evaluacion.toMap());
      await cargarCategorias();
    } catch (e) {
      debugPrint("Error al agregar evaluacion: $e");
    }
  }

  Future<void> actualizarNotaEvaluacion(Evaluacion evaluacion, double? nuevaNota) async {
    try {
      evaluacion.nota = nuevaNota;
      await DatabaseHelper.instance.updateEvaluation(evaluacion.toMap());
      await cargarCategorias(); // Refrescar jerarquia
    } catch (e) {
      debugPrint("Error al actualizar evaluacion: $e");
    }
  }

  Future<void> eliminarEvaluacion(int id) async {
    try {
      await DatabaseHelper.instance.deleteEvaluation(id);
      await cargarCategorias();
    } catch (e) {
      debugPrint("Error al eliminar evaluacion: $e");
    }
  }
}
