import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/// Formatea el monto que el usuario está escribiendo agregando el
/// separador de miles ("10.000" en vez de "10000"), en tiempo real.
class ThousandsInputFormatter extends TextInputFormatter {
  /// Tope de dígitos aceptados. Sin él, pegar una cadena larga hacía
  /// reventar `int.parse` dentro del formatter — y 12 dígitos ya cubren
  /// cualquier monto real en pesos.
  final int maxDigits;

  const ThousandsInputFormatter({this.maxDigits = 12});

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var digitsOnly = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitsOnly.isEmpty) {
      return const TextEditingValue(text: '');
    }
    if (digitsOnly.length > maxDigits) {
      // Se pegó algo más largo que el tope: conservamos lo que ya había
      // en vez de truncar a ciegas.
      if (oldValue.text.replaceAll(RegExp(r'[^0-9]'), '').length <= maxDigits) {
        return oldValue;
      }
      digitsOnly = digitsOnly.substring(0, maxDigits);
    }

    final formatted = NumberFormat.decimalPattern('es_CL').format(int.parse(digitsOnly));

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

/// Texto inicial del campo de monto a partir de un valor ya guardado.
String formatAmountForInput(double amount) =>
    NumberFormat.decimalPattern('es_CL').format(amount.round());
