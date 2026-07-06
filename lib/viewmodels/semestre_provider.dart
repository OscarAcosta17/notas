import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import '../models/semestre.dart';
import '../services/database_helper.dart';

final semestreProvider = NotifierProvider<SemestreNotifier, List<Semestre>>(SemestreNotifier.new);

class SemestreNotifier extends Notifier<List<Semestre>> {
  @override
  List<Semestre> build() {
    cargarSemestres();
    return [];
  }

  Future<void> cargarSemestres() async {
    try {
      final data = await DatabaseHelper.instance.queryAllSemesters();
      state = data.map((e) => Semestre.fromMap(e)).toList();
    } catch (e) {
      debugPrint("Error al cargar semestres: $e");
    }
  }

  Future<void> agregarSemestre(Semestre semestre) async {
    try {
      await DatabaseHelper.instance.insertSemester(semestre.toMap());
      await cargarSemestres();
    } catch (e) {
      debugPrint("Error al agregar semestre: $e");
    }
  }

  Future<void> actualizarSemestre(Semestre semestre) async {
    try {
      await DatabaseHelper.instance.updateSemester(semestre.toMap());
      await cargarSemestres();
    } catch (e) {
      debugPrint("Error al actualizar semestre: $e");
    }
  }

  Future<void> eliminarSemestre(int id) async {
    try {
      await DatabaseHelper.instance.deleteSemester(id);
      await cargarSemestres();
    } catch (e) {
      debugPrint("Error al eliminar semestre: $e");
    }
  }
}
