import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class NumericKeypad extends StatelessWidget {
  final void Function(String key) onKeyPressed;
  final VoidCallback onSubmit;

  const NumericKeypad({
    super.key,
    required this.onKeyPressed,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', 'DEL', '0', 'OK'];

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.urban950,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.urban700),
      ),
      child: GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1.5,
        children: keys.map((key) {
          if (key == 'OK') {
            return _KeyButton(
              onTap: onSubmit,
              background: Colors.white,
              child: const Icon(Icons.check, color: AppColors.urban950),
            );
          }
          if (key == 'DEL') {
            return _KeyButton(
              onTap: () => onKeyPressed('DEL'),
              background: AppColors.urban800,
              child: const Icon(Icons.backspace_outlined, color: AppColors.expense, size: 20),
            );
          }
          return _KeyButton(
            onTap: () => onKeyPressed(key),
            background: AppColors.urban800,
            child: Text(key, style: AppTheme.display(size: 20)),
          );
        }).toList(),
      ),
    );
  }
}

class _KeyButton extends StatelessWidget {
  final VoidCallback onTap;
  final Color background;
  final Widget child;

  const _KeyButton({
    required this.onTap,
    required this.background,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Center(child: child),
      ),
    );
  }
}
