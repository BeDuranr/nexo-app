import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:nexo/widgets/thousands_input_formatter.dart';

TextEditingValue _value(String text) => TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es_CL');
  });

  const formatter = ThousandsInputFormatter();

  group('formatEditUpdate', () {
    test('agrega el separador de miles a medida que se escribe', () {
      expect(formatter.formatEditUpdate(_value(''), _value('1')).text, '1');
      expect(formatter.formatEditUpdate(_value('1'), _value('10')).text, '10');
      expect(formatter.formatEditUpdate(_value('100'), _value('1000')).text, '1.000');
      expect(
        formatter.formatEditUpdate(_value('1.000'), _value('10.000')).text,
        '10.000',
      );
    });

    test('borrar todo deja el campo vacío', () {
      expect(formatter.formatEditUpdate(_value('1.000'), _value('')).text, '');
    });

    test('deja el cursor al final', () {
      final result = formatter.formatEditUpdate(_value('100'), _value('1000'));
      expect(result.selection.baseOffset, result.text.length);
    });

    test('una cadena larguísima no revienta y conserva lo anterior', () {
      final huge = '9' * 30; // antes hacía tirar FormatException a int.parse
      final result = formatter.formatEditUpdate(_value('1.000'), _value(huge));
      expect(result.text, '1.000');
    });

    test('acepta el máximo de dígitos permitido', () {
      final max = '9' * 12;
      expect(formatter.formatEditUpdate(_value(''), _value(max)).text,
          '999.999.999.999');
    });
  });

  group('parseFormattedAmount', () {
    test('convierte el texto con puntos a número', () {
      expect(parseFormattedAmount('10.000'), 10000);
      expect(parseFormattedAmount('1.234.567'), 1234567);
    });

    test('texto vacío o sin dígitos vale cero', () {
      expect(parseFormattedAmount(''), 0);
      expect(parseFormattedAmount('abc'), 0);
    });
  });

  test('formatAmountForInput redondea, no trunca', () {
    expect(formatAmountForInput(1500), '1.500');
    expect(formatAmountForInput(1499.6), '1.500');
  });
}
