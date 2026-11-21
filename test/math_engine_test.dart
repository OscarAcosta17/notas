import 'package:flutter_test/flutter_test.dart';
import 'package:notas/models/categoria_evaluacion.dart';
import 'package:notas/models/evaluacion.dart';
import 'package:notas/models/ramo.dart';

void main() {
  group('CategoriaEvaluacion math engine', () {
    test('returns null when evaluations list is empty or ungraded', () {
      final emptyCat = CategoriaEvaluacion(
        idRamo: 1,
        nombre: 'Certámenes',
        porcentajeTotal: 50,
      );
      expect(emptyCat.calcularPromedio(), isNull);

      final ungradedCat = emptyCat.copyWith(
        evaluaciones: [
          Evaluacion(idCategoria: 1, nombre: 'C1'),
          Evaluacion(idCategoria: 1, nombre: 'C2'),
        ],
      );
      expect(ungradedCat.calcularPromedio(), isNull);
    });

    test('computes arithmetic average for unweighted and weighted evaluations', () {
      final unweighted = CategoriaEvaluacion(
        idRamo: 1,
        nombre: 'Controles',
        porcentajeTotal: 20,
        evaluaciones: [
          Evaluacion(idCategoria: 1, nombre: 'Q1', nota: 5.0),
          Evaluacion(idCategoria: 1, nombre: 'Q2', nota: 7.0),
          Evaluacion(idCategoria: 1, nombre: 'Q3'),
        ],
      );
      expect(unweighted.calcularPromedio(), closeTo(6.0, 1e-6));

      final weighted = CategoriaEvaluacion(
        idRamo: 1,
        nombre: 'Certámenes',
        porcentajeTotal: 60,
        evaluaciones: [
          Evaluacion(idCategoria: 1, nombre: 'C1', porcentajePeso: 40, nota: 4.0),
          Evaluacion(idCategoria: 1, nombre: 'C2', porcentajePeso: 60, nota: 6.5),
        ],
      );
      expect(weighted.calcularPromedio(), closeTo(5.5, 1e-6));
    });

    test('distributes remaining weight across unweighted evaluations in mixed mode', () {
      final mixed = CategoriaEvaluacion(
        idRamo: 1,
        nombre: 'Tareas',
        porcentajeTotal: 30,
        evaluaciones: [
          Evaluacion(idCategoria: 1, nombre: 'T1', porcentajePeso: 50, nota: 6.0),
          Evaluacion(idCategoria: 1, nombre: 'T2', nota: 4.0),
          Evaluacion(idCategoria: 1, nombre: 'T3', nota: 4.0),
        ],
      );
      // T1 has 50%, T2 and T3 share remaining 50% (25% each): 6*0.5 + 4*0.25 + 4*0.25 = 5.0
      expect(mixed.calcularPromedio(), closeTo(5.0, 1e-6));
    });

    test('dropLowest drops single lowest grade only when >1 graded evaluation exists', () {
      final singleGraded = CategoriaEvaluacion(
        idRamo: 1,
        nombre: 'Quizzes',
        porcentajeTotal: 15,
        dropLowest: true,
        evaluaciones: [
          Evaluacion(id: 10, idCategoria: 1, nombre: 'Q1', nota: 3.5),
          Evaluacion(id: 11, idCategoria: 1, nombre: 'Q2'),
        ],
      );
      expect(singleGraded.calcularPromedio(), closeTo(3.5, 1e-6));
      expect(singleGraded.droppedEvaluacionId, isNull);

      final multiGraded = singleGraded.copyWith(
        evaluaciones: [
          Evaluacion(id: 10, idCategoria: 1, nombre: 'Q1', nota: 2.0),
          Evaluacion(id: 11, idCategoria: 1, nombre: 'Q2', nota: 5.0),
          Evaluacion(id: 12, idCategoria: 1, nombre: 'Q3', nota: 7.0),
        ],
      );
      expect(multiGraded.calcularPromedio(), closeTo(6.0, 1e-6));
      expect(multiGraded.droppedEvaluacionId, 10);
    });

    test('computes geometric average and handles 0.0 without throwing or skipping', () {
      final geom = CategoriaEvaluacion(
        idRamo: 1,
        nombre: 'Geom',
        porcentajeTotal: 40,
        averageType: 'Geometrico',
        evaluaciones: [
          Evaluacion(idCategoria: 1, nombre: 'E1', nota: 4.0),
          Evaluacion(idCategoria: 1, nombre: 'E2', nota: 9.0),
        ],
      );
      expect(geom.calcularPromedio(), closeTo(6.0, 1e-6));

      final geomWithZero = geom.copyWith(
        evaluaciones: [
          Evaluacion(idCategoria: 1, nombre: 'E1', nota: 0.0),
          Evaluacion(idCategoria: 1, nombre: 'E2', nota: 7.0),
        ],
      );
      expect(geomWithZero.calcularPromedio(), 0.0);
    });

    test('evaluates custom formulas with e1..eN variables and nested max/min', () {
      final custom = CategoriaEvaluacion(
        idRamo: 1,
        nombre: 'Fórmula USM',
        porcentajeTotal: 100,
        averageType: 'Personalizada',
        customFormula: '0.4 * max(e1, e2, e3) + 0.6 * min(max(e1, e2), e3)',
        evaluaciones: [
          Evaluacion(idCategoria: 1, nombre: 'C1', nota: 3.0),
          Evaluacion(idCategoria: 1, nombre: 'C2', nota: 5.0),
          Evaluacion(idCategoria: 1, nombre: 'C3', nota: 6.0),
        ],
      );
      // max(3,5,6) = 6.0; min(max(3,5), 6) = min(5, 6) = 5.0 -> 0.4*6 + 0.6*5 = 5.4
      expect(custom.calcularPromedio(), closeTo(5.4, 1e-6));
    });

    test('validates custom formulas and rejects syntax errors or division by zero', () {
      expect(
        CategoriaEvaluacion.validateCustomFormula('(e1 + e2) / 2'),
        isNull,
      );
      expect(
        CategoriaEvaluacion.validateCustomFormula('max(e1, e2, e3) * 0.5 + min(e1, e2) * 0.5'),
        isNull,
      );
      expect(
        CategoriaEvaluacion.validateCustomFormula('   '),
        isNotNull,
      );
      expect(
        CategoriaEvaluacion.validateCustomFormula('e1 / 0'),
        contains('no finito'),
      );
      expect(
        CategoriaEvaluacion.validateCustomFormula('(e1 + e2'),
        isNotNull,
      );
    });
  });

  group('Ramo grade aggregation', () {
    test('normalizes arithmetic average ignoring 0%-weight categories', () {
      final ramo = Ramo(
        idSemestre: 1,
        nombre: 'Física General',
        tipoPromedio: 'Aritmetico',
        tieneGlobal: false,
        reemplazaPeorNota: false,
        notaAprobacion: 4.0,
        categorias: [
          CategoriaEvaluacion(
            idRamo: 1,
            nombre: 'Certámenes',
            porcentajeTotal: 30,
            evaluaciones: [Evaluacion(idCategoria: 1, nombre: 'C1', nota: 5.0)],
          ),
          CategoriaEvaluacion(
            idRamo: 1,
            nombre: 'Tareas',
            porcentajeTotal: 30,
            evaluaciones: [Evaluacion(idCategoria: 2, nombre: 'T1', nota: 7.0)],
          ),
          CategoriaEvaluacion(
            idRamo: 1,
            nombre: 'Aula USM',
            porcentajeTotal: 0,
            evaluaciones: [Evaluacion(idCategoria: 3, nombre: 'Entrega', nota: 1.0)],
          ),
        ],
      );
      expect(ramo.calcularNotaActual(), 6.0);
    });

    test('computes geometric ramo average and yields 0.0 if any weighted category is 0.0', () {
      final geomRamo = Ramo(
        idSemestre: 1,
        nombre: 'Matemáticas',
        tipoPromedio: 'Geometrico',
        tieneGlobal: false,
        reemplazaPeorNota: false,
        notaAprobacion: 55.0,
        categorias: [
          CategoriaEvaluacion(
            idRamo: 1,
            nombre: 'Cat A',
            porcentajeTotal: 50,
            evaluaciones: [Evaluacion(idCategoria: 1, nombre: 'E1', nota: 4.0)],
          ),
          CategoriaEvaluacion(
            idRamo: 1,
            nombre: 'Cat B',
            porcentajeTotal: 50,
            evaluaciones: [Evaluacion(idCategoria: 2, nombre: 'E2', nota: 9.0)],
          ),
        ],
      );
      expect(geomRamo.calcularNotaActual(), 6.0);

      final geomWithZeroCat = geomRamo.copyWith(
        categorias: [
          CategoriaEvaluacion(
            idRamo: 1,
            nombre: 'Cat A',
            porcentajeTotal: 50,
            evaluaciones: [Evaluacion(idCategoria: 1, nombre: 'E1', nota: 0.0)],
          ),
          CategoriaEvaluacion(
            idRamo: 1,
            nombre: 'Cat B',
            porcentajeTotal: 50,
            evaluaciones: [Evaluacion(idCategoria: 2, nombre: 'E2', nota: 9.0)],
          ),
        ],
      );
      expect(geomWithZeroCat.calcularNotaActual(), 0.0);
    });
  });
}
