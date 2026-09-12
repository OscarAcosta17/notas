import 'package:math_expressions/math_expressions.dart';

void main() {
  Parser p = Parser();
  ContextModel cm = ContextModel();
  
  try {
    print(p.parse('sqrt(4)').evaluate(EvaluationType.REAL, cm));
    print(p.parse('4^2').evaluate(EvaluationType.REAL, cm));
    print(p.parse('abs(-5)').evaluate(EvaluationType.REAL, cm));
  } catch (e) {
    print('Error: \');
  }
}
