import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import '../models/ramo.dart';
import '../services/database_helper.dart';

final ramoProvider = NotifierProvider.family<RamoNotifier, List<Ramo>, int>((int arg) {
  final notifier = RamoNotifier();
  notifier.arg = arg;
  return notifier;
});

class RamoNotifier extends Notifier<List<Ramo>> {
  late int arg;

  @override
  List<Ramo> build() {
    cargarRamos();
    return [];
  }

  Future<void> cargarRamos() async {
    try {
      final data = await DatabaseHelper.instance.querySubjectsBySemester(arg);
      state = data.map((e) => Ramo.fromMap(e)).toList();
    } catch (e) {
      debugPrint("Error al cargar ramos: $e");
    }
  }

  Future<void> agregarRamo(Ramo ramo) async {
    try {
      await DatabaseHelper.instance.insertSubject(ramo.toMap());
      await cargarRamos();
    } catch (e) {
      debugPrint("Error al agregar ramo: $e");
    }
  }

  Future<void> actualizarRamo(Ramo ramo) async {
    try {
      await DatabaseHelper.instance.updateSubject(ramo.toMap());
      await cargarRamos();
    } catch (e) {
      debugPrint("Error al actualizar ramo: $e");
    }
  }

  Future<void> eliminarRamo(int id) async {
    try {
      await DatabaseHelper.instance.deleteSubject(id);
      await cargarRamos();
    } catch (e) {
      debugPrint("Error al eliminar ramo: $e");
    }
  }
}
