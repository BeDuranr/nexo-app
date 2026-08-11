/// Una categoría es un nombre + un ícono (clave de lib/utils/category_icons.dart).
/// No está atada a "gasto" o "ingreso": una misma categoría (ej.
/// "Freelance") puede usarse para ambos tipos de movimiento. El tipo se
/// elige aparte, en el toggle Gasto/Ingreso de la pantalla de registro.
class CategoryModel {
  final int? id;
  final String name;
  final String iconKey;
  final bool isDefault;

  const CategoryModel({
    this.id,
    required this.name,
    required this.iconKey,
    this.isDefault = false,
  });

  CategoryModel copyWith({
    int? id,
    String? name,
    String? iconKey,
    bool? isDefault,
  }) {
    return CategoryModel(
      id: id ?? this.id,
      name: name ?? this.name,
      iconKey: iconKey ?? this.iconKey,
      isDefault: isDefault ?? this.isDefault,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'icon_key': iconKey,
      'is_default': isDefault ? 1 : 0,
    };
  }

  factory CategoryModel.fromMap(Map<String, dynamic> map) {
    return CategoryModel(
      id: map['id'] as int?,
      name: map['name'] as String,
      iconKey: map['icon_key'] as String? ?? 'other',
      isDefault: (map['is_default'] as int? ?? 0) == 1,
    );
  }
}
