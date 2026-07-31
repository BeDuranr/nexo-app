import 'package:flutter/material.dart';

import '../models/category_model.dart';
import '../theme/app_theme.dart';

class CategoryGrid extends StatelessWidget {
  final List<CategoryModel> categories;
  final CategoryModel? selected;
  final void Function(CategoryModel) onSelect;
  final VoidCallback onAddNew;
  final void Function(CategoryModel)? onLongPress;

  const CategoryGrid({
    super.key,
    required this.categories,
    required this.selected,
    required this.onSelect,
    required this.onAddNew,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.6,
      children: [
        ...categories.map((cat) {
          final isSelected = selected?.id == cat.id;
          return _CategoryChip(
            emoji: cat.emoji,
            name: cat.name,
            selected: isSelected,
            onTap: () => onSelect(cat),
            onLongPress: onLongPress != null ? () => onLongPress!(cat) : null,
          );
        }),
        _AddCategoryChip(onTap: onAddNew),
      ],
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String emoji;
  final String name;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _CategoryChip({
    required this.emoji,
    required this.name,
    required this.selected,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.urban700 : AppColors.urban800,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColors.urbanBlue : AppColors.urban700,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                    color: selected ? Colors.white : AppColors.urban300,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddCategoryChip extends StatelessWidget {
  final VoidCallback onTap;
  const _AddCategoryChip({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.urban900,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.urban600, style: BorderStyle.solid),
          ),
          child: const Center(
            child: Icon(Icons.add, color: AppColors.urban300, size: 18),
          ),
        ),
      ),
    );
  }
}
