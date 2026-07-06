class ClaseHorario {
  int? id;
  int semesterId;
  String subjectName;
  int diaSemana; // 1 = Lunes, 2 = Martes, ..., 7 = Domingo
  int bloque; // 1, 3, 5, 7, 9, 11, 13, 15
  String sala;
  String paralelo;

  ClaseHorario({
    this.id,
    required this.semesterId,
    required this.subjectName,
    required this.diaSemana,
    required this.bloque,
    required this.sala,
    required this.paralelo,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'semester_id': semesterId,
      'subject_name': subjectName,
      'dia_semana': diaSemana,
      'bloque': bloque,
      'sala': sala,
      'paralelo': paralelo,
    };
  }

  factory ClaseHorario.fromMap(Map<String, dynamic> map) {
    return ClaseHorario(
      id: map['id'] as int?,
      semesterId: map['semester_id'] as int,
      subjectName: map['subject_name'] as String,
      diaSemana: map['dia_semana'] as int,
      bloque: map['bloque'] as int,
      sala: map['sala'] as String,
      paralelo: map['paralelo'] as String,
    );
  }
}
