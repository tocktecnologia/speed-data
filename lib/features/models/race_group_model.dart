
class RaceGroup {
  final String id;
  final String name;
  final String description;

  RaceGroup({
    required this.id,
    required this.name,
    this.description = '',
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
    };
  }

  factory RaceGroup.fromMap(Map<String, dynamic> map) {
    return RaceGroup(
      id: map['id'] is String ? map['id'] : '',
      name: map['name'] is String ? map['name'] : '',
      description: map['description'] is String ? map['description'] : '',
    );
  }
}
