import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/// Formatea el monto que el usuario está escribiendo agregando el
/// separador de miles ("10.000" en vez de "10000"), en tiempo real.
class ThousandsInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digitsOnly = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitsOnly.isEmpty) {
      return const TextEditingValue(text: '');
    }

    final number = int.parse(digitsOnly);
    final formatted = NumberFormat.decimalPattern('es_CL').format(number);

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

/// Convierte de vuelta el texto formateado (con puntos) a un número.
double parseFormattedAmount(String text) {
  final digitsOnly = text.replaceAll(RegExp(r'[^0-9]'), '');
  if (digitsOnly.isEmpty) return 0;
  return double.parse(digitsOnly);
}
