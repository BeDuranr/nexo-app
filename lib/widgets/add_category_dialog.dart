import 'package:flutter/material.dart';

import '../models/category_model.dart';
import '../theme/app_theme.dart';
import '../utils/category_icons.dart';

/// Grilla de íconos reutilizable dentro de los diálogos de categoría.
class _IconPicker extends StatelessWidget {
  final String selectedKey;
  final void Function(String) onSelect;

  const _IconPicker({required this.selectedKey, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 180,
      width: double.maxFinite,
      child: GridView.count(
        crossAxisCount: 5,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        children: categoryIcons.entries.map((entry) {
          final isSelected = entry.key == selectedKey;
          final color = colorForKey(entry.key);
          return InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => onSelect(entry.key),
            child: Container(
              decoration: BoxDecoration(
                color: isSelected ? color.withOpacity(0.2) : AppColors.urban800,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSelected ? color : AppColors.urban700,
                  width: isSelected ? 2 : 1,
                ),
              ),
              child: Icon(entry.value, color: color, size: 20),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// Muestra el diálogo y retorna la nueva categoría, o null si se cancela.
/// Las categorías no tienen tipo: sirven tanto para gastos como ingresos.
Future<CategoryModel?> showAddCategoryDialog(BuildContext context) {
  final nameController = TextEditingController();
  String selectedIconKey = 'other';

  return showDialog<CategoryModel>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setState) {
          return AlertDialog(
            backgroundColor: AppColors.urban900,
            title: const Text('Nueva categoría', style: TextStyle(color: Colors.white)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  autofocus: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(hintText: 'Nombre de la categoría'),
                ),
                const SizedBox(height: 12),
                _IconPicker(
                  selectedKey: selectedIconKey,
                  onSelect: (key) => setState(() => selectedIconKey = key),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () {
                  final name = nameController.text.trim();
                  if (name.isEmpty) return;
                  Navigator.pop(ctx, CategoryModel(name: name, iconKey: selectedIconKey));
                },
                child: const Text('Crear'),
              ),
            ],
          );
        },
      );
    },
  );
}

/// Resultado de editar una categoría existente: guardar cambios o eliminarla.
class CategoryEditResult {
  final CategoryModel? category; // no-nulo cuando la acción fue "guardar"
  final bool isDelete;

  const CategoryEditResult.save(this.category) : isDelete = false;
  const CategoryEditResult.delete()
      : category = null,
        isDelete = true;
}

/// Muestra el diálogo para editar una categoría existente (incluidas las
/// que vienen por defecto). Retorna null si se cancela.
Future<CategoryEditResult?> showEditCategoryDialog(
  BuildContext context,
  CategoryModel category,
) {
  final nameController = TextEditingController(text: category.name);
  String selectedIconKey = category.iconKey;

  return showDialog<CategoryEditResult>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setState) {
          return AlertDialog(
            backgroundColor: AppColors.urban900,
            title: const Text('Editar categoría', style: TextStyle(color: Colors.white)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  autofocus: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(hintText: 'Nombre de la categoría'),
                ),
                const SizedBox(height: 12),
                _IconPicker(
                  selectedKey: selectedIconKey,
                  onSelect: (key) => setState(() => selectedIconKey = key),
                ),
              ],
            ),
            actions: [
              SizedBox(
                width: double.maxFinite,
                child: Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, const CategoryEditResult.delete()),
                      child: const Text('Eliminar', style: TextStyle(color: AppColors.expense)),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancelar'),
                    ),
                    FilledButton(
                      onPressed: () {
                        final name = nameController.text.trim();
                        if (name.isEmpty) return;
                        Navigator.pop(
                          ctx,
                          CategoryEditResult.save(
                              category.copyWith(name: name, iconKey: selectedIconKey)),
                        );
                      },
                      child: const Text('Guardar'),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      );
    },
  );
}

/// Confirma antes de eliminar definitivamente una categoría. Los
/// movimientos ya registrados con ella conservan su ícono guardado,
/// así que no se ven afectados.
Future<bool> confirmDeleteCategory(BuildContext context, String categoryName) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.urban900,
      title: const Text('¿Eliminar categoría?', style: TextStyle(color: Colors.white)),
      content: Text(
        'Se eliminará "$categoryName" de la lista. Los movimientos ya registrados con esta categoría no se ven afectados.',
        style: const TextStyle(color: AppColors.urban300),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Eliminar', style: TextStyle(color: AppColors.expense)),
        ),
      ],
    ),
  );
  return confirmed == true;
}
