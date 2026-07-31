/// Una categoría es solo un nombre + emoji. No está atada a "gasto" o
/// "ingreso": una misma categoría (ej. "Freelance") puede usarse para
/// ambos tipos de movimiento. El tipo se elige aparte, en el toggle
/// Gasto/Ingreso de la pantalla de registro.
class CategoryModel {
  final int? id;
  final String name;
  final String emoji;
  final bool isDefault;

  const CategoryModel({
    this.id,
    required this.name,
    required this.emoji,
    this.isDefault = false,
  });

  CategoryModel copyWith({
    int? id,
    String? name,
    String? emoji,
    bool? isDefault,
  }) {
    return CategoryModel(
      id: id ?? this.id,
      name: name ?? this.name,
      emoji: emoji ?? this.emoji,
      isDefault: isDefault ?? this.isDefault,
    );
  }

  /// Nombre + emoji, tal como se muestra en el mockup ("Metro 🚇").
  String get label => '$name $emoji';

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'emoji': emoji,
      'is_default': isDefault ? 1 : 0,
    };
  }

  factory CategoryModel.fromMap(Map<String, dynamic> map) {
    return CategoryModel(
      id: map['id'] as int?,
      name: map['name'] as String,
      emoji: map['emoji'] as String,
      isDefault: (map['is_default'] as int? ?? 0) == 1,
    );
  }
}
