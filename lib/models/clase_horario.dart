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
    final rawDay = (map['dia_semana'] as num?)?.toInt() ?? 1;
    final safeDay = (rawDay >= 1 && rawDay <= 7) ? rawDay : 1;
    return ClaseHorario(
      id: (map['id'] as num?)?.toInt(),
      semesterId: (map['semester_id'] as num?)?.toInt() ?? 0,
      subjectName: (map['subject_name'] ?? '').toString(),
      diaSemana: safeDay,
      bloque: (map['bloque'] as num?)?.toInt() ?? 1,
      sala: (map['sala'] ?? '').toString(),
      paralelo: (map['paralelo'] ?? '').toString(),
    );
  }
}
