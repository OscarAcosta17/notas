class Semestre {
  int? id;
  String nombre;

  Semestre({this.id, required this.nombre});

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': nombre,
    };
  }

  factory Semestre.fromMap(Map<String, dynamic> map) {
    return Semestre(
      id: map['id'],
      nombre: map['name'],
    );
  }
}
