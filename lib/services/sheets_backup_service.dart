import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/category_model.dart';
import '../models/debt_model.dart';
import '../models/transaction_model.dart';

/// Falla esperable del respaldo (sin red, token vencido, planilla
/// editada a mano y ya ilegible). Lleva un mensaje listo para mostrar.
class SheetsBackupException implements Exception {
  SheetsBackupException(this.message, {this.detail});

  final String message;
  final String? detail;

  @override
  String toString() => detail == null ? message : '$message ($detail)';
}

/// Lo que hay guardado en la planilla, ya parseado.
class BackupSnapshot {
  const BackupSnapshot({
    required this.categories,
    required this.transactions,
    this.debts = const [],
  });

  final List<CategoryModel> categories;
  final List<TransactionModel> transactions;

  /// Vacía en las planillas anteriores al formato 3, que no tenían deudas.
  final List<DebtModel> debts;

  bool get isEmpty => categories.isEmpty && transactions.isEmpty;
}

/// Respaldo de los datos de Nexo en una hoja de cálculo de Google.
///
/// Habla con las APIs REST de Sheets y Drive directamente, con el token
/// que da `GoogleAuthService`. El scope es `drive.file`, así que todo
/// esto solo alcanza a la planilla que la app misma creó.
class SheetsBackupService {
  SheetsBackupService({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  static const String _driveFiles = 'https://www.googleapis.com/drive/v3/files';
  static const String _sheetsApi =
      'https://sheets.googleapis.com/v4/spreadsheets';

  /// Etiqueta privada de la app sobre el archivo de Drive. Es lo que
  /// permite reencontrar la planilla después de reinstalar la app, cuando
  /// el id guardado en SQLite ya no está.
  ///
  /// No es la versión del formato y no debe cambiar nunca: una app que
  /// busque otro valor no encontraría las planillas ya creadas, y crearía
  /// una vacía al lado.
  static const String _tagKey = 'nexoRespaldo';
  static const String _tagValue = 'v1';

  /// Versión del contenido de la planilla, anotada en la hoja `info`.
  /// La 1 tenía encabezados técnicos, fechas ISO y tipos en inglés. La 3
  /// suma la hoja `deudas` y la columna "Deuda" al final de movimientos.
  static const int _formatVersion = 3;

  static const String spreadsheetTitle = 'Nexo — Respaldo';

  static const String _sheetTransactions = 'movimientos';
  static const String _sheetCategories = 'categorias';
  static const String _sheetDebts = 'deudas';
  static const String _sheetInfo = 'info';

  static const List<String> _categoryHeader = [
    'ID',
    'Nombre',
    'Ícono',
    'Por defecto',
  ];
  static const List<String> _transactionHeader = [
    ..._transactionHeaderV2,
    'Deuda',
  ];
  static const List<String> _debtHeader = [
    'ID',
    'Nombre',
    'Monto total',
    'Cuotas',
    'Primera cuota',
  ];

  /// Encabezado de movimientos del formato 2: el mismo del 3 sin la
  /// columna "Deuda", que va al final justamente para que las columnas
  /// anteriores no se corran.
  static const List<String> _transactionHeaderV2 = [
    'ID',
    'Fecha',
    'Tipo',
    'Monto',
    'ID categoría',
    'Categoría',
    'Ícono',
    'Nota',
  ];

  /// Encabezados del formato 1. Las columnas están en el mismo orden, así
  /// que se siguen aceptando al restaurar: una planilla vieja que todavía
  /// no pasó por un respaldo nuevo tiene que poder restaurarse igual.
  static const List<String> _categoryHeaderV1 = [
    'id',
    'nombre',
    'icono',
    'por_defecto',
  ];
  static const List<String> _transactionHeaderV1 = [
    'id',
    'fecha',
    'tipo',
    'monto',
    'categoria_id',
    'categoria',
    'icono',
    'nota',
  ];

  static const String _expenseLabel = 'Gasto';
  static const String _incomeLabel = 'Ingreso';

  /// Lo que muestran las celdas de fecha y monto. Es solo formato
  /// visual: el valor guardado sigue siendo un número, que es lo que se
  /// lee al restaurar.
  static const String _datePattern = 'dd/mm/yyyy hh:mm';
  static const String _dayPattern = 'dd/mm/yyyy';
  static const String _amountPattern = r'$#,##0';

  /// Con este locale Sheets agrupa los miles con punto, como la app.
  static const String _locale = 'es_CL';

  Map<String, String> _headers(String token) => {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

  /// Devuelve el id de la planilla de respaldo, creándola si hace falta.
  ///
  /// [cachedId] es el id que la app tenía anotado. Se verifica antes de
  /// confiar en él: el usuario pudo haber mandado la planilla a la
  /// papelera desde Drive, y en ese caso hay que crear otra.
  Future<String> ensureSpreadsheet(String token, {String? cachedId}) async {
    if (cachedId != null && await _existsAndUsable(token, cachedId)) {
      return cachedId;
    }
    final found = await _findSpreadsheet(token);
    if (found != null) return found;
    return _createSpreadsheet(token);
  }

  Future<bool> _existsAndUsable(String token, String id) async {
    final response = await _get(
      Uri.parse('$_driveFiles/$id?fields=id,trashed'),
      token,
      allowNotFound: true,
    );
    if (response == null) return false;
    return (response['trashed'] as bool?) != true;
  }

  Future<String?> _findSpreadsheet(String token) async {
    const query = "appProperties has { key='$_tagKey' and value='$_tagValue' } "
        'and trashed = false';
    final uri = Uri.parse(_driveFiles).replace(queryParameters: {
      'q': query,
      'fields': 'files(id,name)',
      'pageSize': '10',
    });

    final body = await _get(uri, token);
    final files = (body?['files'] as List<dynamic>?) ?? const [];
    if (files.isEmpty) return null;
    return (files.first as Map<String, dynamic>)['id'] as String;
  }

  Future<String> _createSpreadsheet(String token) async {
    final created = await _post(
      Uri.parse(_sheetsApi),
      token,
      {
        'properties': {'title': spreadsheetTitle, 'locale': _locale},
        'sheets': [
          {
            'properties': {'title': _sheetTransactions}
          },
          {
            'properties': {'title': _sheetCategories}
          },
          {
            'properties': {'title': _sheetInfo}
          },
        ],
      },
    );

    final id = created['spreadsheetId'] as String?;
    if (id == null) {
      throw SheetsBackupException('Google no devolvió el id de la planilla.');
    }

    // La etiqueta va aparte porque es un campo de Drive, no de Sheets.
    // Sin esto la planilla se vuelve imposible de reencontrar si la app
    // se reinstala y se pierde el id guardado.
    await _patch(
      Uri.parse('$_driveFiles/$id'),
      token,
      {
        'appProperties': {_tagKey: _tagValue},
      },
    );

    return id;
  }

  /// Sube el estado completo, reemplazando todo lo que había. No es
  /// incremental a propósito — con el volumen de esta app un dump entero
  /// es más simple de razonar y no puede quedar desincronizado.
  ///
  /// Todas las hojas se reemplazan en **un solo** `batchUpdate`, que Google
  /// aplica entero o no aplica. Antes cada hoja se borraba y se reescribía
  /// en llamadas separadas: si iOS suspendía la app entre medio (al
  /// salir, que es justo cuando corre el respaldo automático), la hoja de
  /// movimientos quedaba vacía hasta el próximo respaldo.
  Future<void> upload({
    required String token,
    required String spreadsheetId,
    required List<CategoryModel> categories,
    required List<TransactionModel> transactions,
    List<DebtModel> debts = const [],
  }) async {
    final tabs = <String, List<List<Object?>>>{
      _sheetCategories: [
        _categoryHeader,
        for (final category in categories)
          [
            category.id,
            category.name,
            category.iconKey,
            category.isDefault ? 'Sí' : 'No',
          ],
      ],
      _sheetTransactions: [
        _transactionHeader,
        for (final tx in transactions)
          [
            tx.id,
            dateToSerial(tx.date),
            tx.type == MovementType.income ? _incomeLabel : _expenseLabel,
            tx.amount,
            tx.categoryId,
            tx.categoryName,
            tx.categoryIconKey,
            tx.note,
            tx.debtId,
          ],
      ],
      _sheetDebts: [
        _debtHeader,
        for (final debt in debts)
          [
            debt.id,
            debt.name,
            debt.totalAmount,
            debt.installments,
            dateToSerial(debt.firstDate),
          ],
      ],
      _sheetInfo: [
        ['Dato', 'Valor'],
        ['Última actualización', dateToSerial(DateTime.now())],
        ['Movimientos', transactions.length],
        ['Categorías', categories.length],
        ['Deudas', debts.length],
        ['Formato', _formatVersion],
      ],
    };

    final sheetIds = await _ensureTabs(token, spreadsheetId, tabs.keys);

    await _post(
      Uri.parse('$_sheetsApi/$spreadsheetId:batchUpdate'),
      token,
      {
        'requests': [
          for (final tab in tabs.entries)
            ..._replaceTabRequests(sheetIds[tab.key]!, tab.value),
        ],
      },
    );

    await _applyFormatting(token, spreadsheetId, sheetIds);
  }

  /// Id numérico de cada hoja, que es lo que piden los `batchUpdate`.
  /// Si alguien borró una hoja a mano desde Drive, se vuelve a crear.
  Future<Map<String, int>> _ensureTabs(
    String token,
    String spreadsheetId,
    Iterable<String> titles,
  ) async {
    final sheetIds = await _existingTabs(token, spreadsheetId);

    final missing = titles.where((t) => !sheetIds.containsKey(t)).toList();
    if (missing.isEmpty) return sheetIds;

    final added = await _post(
      Uri.parse('$_sheetsApi/$spreadsheetId:batchUpdate'),
      token,
      {
        'requests': [
          for (final title in missing)
            {
              'addSheet': {
                'properties': {'title': title},
              },
            },
        ],
      },
    );
    for (final reply in (added['replies'] as List<dynamic>?) ?? const []) {
      final props = ((reply as Map<String, dynamic>)['addSheet']
          as Map<String, dynamic>)['properties'] as Map<String, dynamic>;
      sheetIds[props['title'] as String] = props['sheetId'] as int;
    }
    return sheetIds;
  }

  /// Id numérico de cada hoja que ya existe, por título.
  Future<Map<String, int>> _existingTabs(
      String token, String spreadsheetId) async {
    final body = await _get(
      Uri.parse('$_sheetsApi/$spreadsheetId').replace(
          queryParameters: {'fields': 'sheets.properties(sheetId,title)'}),
      token,
    );
    final sheetIds = <String, int>{};
    for (final sheet in (body?['sheets'] as List<dynamic>?) ?? const []) {
      final props =
          (sheet as Map<String, dynamic>)['properties'] as Map<String, dynamic>;
      sheetIds[props['title'] as String] = props['sheetId'] as int;
    }
    return sheetIds;
  }

  /// Deja la hoja con exactamente [rows]: primero ajusta el tamaño de la
  /// grilla y después escribe cada celda.
  ///
  /// Achicar la grilla es lo que borra las filas sobrantes cuando el
  /// respaldo nuevo tiene menos movimientos que el anterior. Agrandarla es
  /// lo que permite pasar las 1000 filas con las que viene una hoja nueva.
  /// Sobra una fila vacía al final porque Sheets no deja fijar el
  /// encabezado si es la única fila de la hoja.
  List<Map<String, Object?>> _replaceTabRequests(
    int sheetId,
    List<List<Object?>> rows,
  ) =>
      [
        {
          'updateSheetProperties': {
            'properties': {
              'sheetId': sheetId,
              'gridProperties': {
                'rowCount': rows.length + 1,
                'columnCount': rows.first.length,
              },
            },
            'fields': 'gridProperties.rowCount,gridProperties.columnCount',
          },
        },
        {
          'updateCells': {
            'start': {'sheetId': sheetId, 'rowIndex': 0, 'columnIndex': 0},
            'rows': [
              for (final row in rows)
                {
                  'values': [for (final cell in row) _cell(cell)],
                },
            ],
            // Con esta máscara una celda sin valor se vacía, así que no
            // queda texto viejo debajo de una nota que ahora está vacía.
            'fields': 'userEnteredValue',
          },
        },
      ];

  /// Celda tal cual, sin interpretar: un texto que empiece con "=" queda
  /// como texto, no como fórmula (lo mismo que hacía `RAW`).
  Map<String, Object?> _cell(Object? value) {
    if (value is num) {
      return {
        'userEnteredValue': {'numberValue': value},
      };
    }
    final text = value?.toString() ?? '';
    if (text.isEmpty) return const {};
    return {
      'userEnteredValue': {'stringValue': text},
    };
  }

  /// Negrita y fila fija en los encabezados, y formato de fecha y monto.
  ///
  /// Se aplica en cada respaldo porque es idempotente y así también
  /// alcanza a las planillas creadas antes de que existiera. Va en un
  /// `batchUpdate` aparte del de los datos, y si falla no se considera un
  /// respaldo fallido: los datos ya quedaron escritos, y marcar el
  /// respaldo como pendiente por un tema visual haría reintentar para
  /// siempre.
  Future<void> _applyFormatting(
    String token,
    String spreadsheetId,
    Map<String, int> sheetIds,
  ) async {
    try {
      final requests = <Map<String, Object?>>[
        {
          'updateSpreadsheetProperties': {
            'properties': {'locale': _locale},
            'fields': 'locale',
          },
        },
        for (final id in sheetIds.values) ..._headerRequests(id),
      ];

      final transactionsId = sheetIds[_sheetTransactions];
      if (transactionsId != null) {
        requests
          ..add(_numberFormat(transactionsId, column: 1, type: 'DATE_TIME',
              pattern: _datePattern))
          ..add(_numberFormat(transactionsId, column: 3, type: 'CURRENCY',
              pattern: _amountPattern));
      }

      final debtsId = sheetIds[_sheetDebts];
      if (debtsId != null) {
        requests
          ..add(_numberFormat(debtsId, column: 2, type: 'CURRENCY',
              pattern: _amountPattern))
          ..add(_numberFormat(debtsId, column: 4, type: 'DATE',
              pattern: _dayPattern));
      }

      final infoId = sheetIds[_sheetInfo];
      if (infoId != null) {
        requests.add(_numberFormat(infoId,
            column: 1, row: 1, type: 'DATE_TIME', pattern: _datePattern));
      }

      await _post(
        Uri.parse('$_sheetsApi/$spreadsheetId:batchUpdate'),
        token,
        {'requests': requests},
      );
    } on SheetsBackupException {
      // Ver el comentario del método: el formato es cosmético.
    }
  }

  List<Map<String, Object?>> _headerRequests(int sheetId) => [
        {
          'repeatCell': {
            'range': {'sheetId': sheetId, 'startRowIndex': 0, 'endRowIndex': 1},
            'cell': {
              'userEnteredFormat': {
                'textFormat': {'bold': true},
              },
            },
            'fields': 'userEnteredFormat.textFormat.bold',
          },
        },
        {
          'updateSheetProperties': {
            'properties': {
              'sheetId': sheetId,
              'gridProperties': {'frozenRowCount': 1},
            },
            'fields': 'gridProperties.frozenRowCount',
          },
        },
      ];

  /// Formato de número para una columna entera desde la fila 2 (o solo
  /// para la celda de [row], si se indica).
  Map<String, Object?> _numberFormat(
    int sheetId, {
    required int column,
    int? row,
    required String type,
    required String pattern,
  }) =>
      {
        'repeatCell': {
          'range': {
            'sheetId': sheetId,
            'startRowIndex': row ?? 1,
            if (row != null) 'endRowIndex': row + 1,
            'startColumnIndex': column,
            'endColumnIndex': column + 1,
          },
          'cell': {
            'userEnteredFormat': {
              'numberFormat': {'type': type, 'pattern': pattern},
            },
          },
          'fields': 'userEnteredFormat.numberFormat',
        },
      };

  /// Origen de las fechas de Sheets: el valor de una celda de fecha es la
  /// cantidad de días desde acá, con la hora como fracción.
  static final DateTime _sheetsEpoch = DateTime.utc(1899, 12, 30);

  /// Fecha como número de serie de Sheets, para que la celda sea una fecha
  /// de verdad (ordenable y filtrable) y no texto.
  ///
  /// Se toman los componentes de la hora local tal cual, sin pasar por
  /// UTC: es lo que la app guarda en SQLite, y la celda no tiene zona
  /// horaria.
  static double dateToSerial(DateTime date) {
    final asUtc = DateTime.utc(date.year, date.month, date.day, date.hour,
        date.minute, date.second, date.millisecond);
    return asUtc.difference(_sheetsEpoch).inMilliseconds /
        Duration.millisecondsPerDay;
  }

  /// Inversa de [dateToSerial]. Se redondea al milisegundo para absorber
  /// el error del punto flotante.
  static DateTime serialToDate(num serial) {
    final utc = _sheetsEpoch.add(Duration(
        milliseconds: (serial * Duration.millisecondsPerDay).round()));
    return DateTime(utc.year, utc.month, utc.day, utc.hour, utc.minute,
        utc.second, utc.millisecond);
  }

  /// Lee la planilla y devuelve lo que haya, ya parseado y validado.
  Future<BackupSnapshot> download({
    required String token,
    required String spreadsheetId,
  }) async {
    final categoryRows = await _readTab(token, spreadsheetId, _sheetCategories);
    final transactionRows =
        await _readTab(token, spreadsheetId, _sheetTransactions);

    // Las planillas de los formatos 1 y 2 no tienen esta hoja, y pedir
    // una hoja que no existe es un error de Sheets, no una lista vacía.
    final tabs = await _existingTabs(token, spreadsheetId);
    final debtRows = tabs.containsKey(_sheetDebts)
        ? await _readTab(token, spreadsheetId, _sheetDebts)
        : const <List<dynamic>>[];

    return BackupSnapshot(
      categories: parseCategories(categoryRows),
      transactions: parseTransactions(transactionRows),
      debts: parseDebts(debtRows),
    );
  }

  Future<List<List<dynamic>>> _readTab(
    String token,
    String spreadsheetId,
    String tab,
  ) async {
    final uri = Uri.parse('$_sheetsApi/$spreadsheetId/values/$tab').replace(
      // Sin esto los montos vuelven como texto ya formateado ("1.234")
      // y habría que deshacer el formato para recuperar el número.
      queryParameters: {'valueRenderOption': 'UNFORMATTED_VALUE'},
    );

    final body = await _get(uri, token);
    final values = (body?['values'] as List<dynamic>?) ?? const [];
    return values.map((row) => (row as List<dynamic>)).toList();
  }

  /// Expuesto para los tests: parsear es la parte que puede corromper
  /// datos reales, y se puede verificar sin red.
  List<CategoryModel> parseCategories(List<List<dynamic>> rows) {
    if (rows.isEmpty) return const [];
    _checkHeader(
        rows.first, [_categoryHeader, _categoryHeaderV1], _sheetCategories);

    final categories = <CategoryModel>[];
    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (_isBlank(row)) continue;

      final name = _text(row, 1);
      if (name.isEmpty) continue;

      categories.add(CategoryModel(
        id: _intOrNull(row, 0),
        name: name,
        iconKey: _textOr(row, 2, 'other'),
        isDefault: _isYes(row, 3),
      ));
    }
    return categories;
  }

  /// "Sí" en el formato 2, 1 en el 1. Cualquier otra cosa es "no": que
  /// una categoría deje de ser por defecto no pierde ningún dato.
  bool _isYes(List<dynamic> row, int index) {
    final value = _normalize(_text(row, index));
    return value == 'si' || value == '1';
  }

  List<TransactionModel> parseTransactions(List<List<dynamic>> rows) {
    if (rows.isEmpty) return const [];
    _checkHeader(
        rows.first,
        [_transactionHeader, _transactionHeaderV2, _transactionHeaderV1],
        _sheetTransactions);

    final transactions = <TransactionModel>[];
    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (_isBlank(row)) continue;

      final date = _dateOrNull(row, 1);
      if (date == null) {
        final rawDate = _text(row, 1);
        throw SheetsBackupException(
          'La fila ${i + 1} de "$_sheetTransactions" tiene una fecha ilegible.',
          detail: rawDate.isEmpty ? 'vacía' : rawDate,
        );
      }

      final type = _typeOrNull(row, 2);
      if (type == null) {
        // Antes un tipo desconocido se leía como gasto. Con la columna en
        // español es fácil tipear "Ingresos" a mano, y convertir en
        // silencio un ingreso en gasto descuadra todos los saldos.
        throw SheetsBackupException(
          'La fila ${i + 1} de "$_sheetTransactions" tiene un tipo ilegible.',
          detail: '${_text(row, 2)} (se esperaba Gasto o Ingreso)',
        );
      }

      final amount = _doubleOrNull(row, 3);
      if (amount == null) {
        throw SheetsBackupException(
          'La fila ${i + 1} de "$_sheetTransactions" tiene un monto ilegible.',
          detail: _text(row, 3),
        );
      }

      transactions.add(TransactionModel(
        id: _intOrNull(row, 0),
        date: date,
        type: type,
        amount: amount,
        categoryId: _intOr(row, 4, 0),
        categoryName: _textOr(row, 5, 'Sin categoría'),
        categoryIconKey: _textOr(row, 6, 'other'),
        note: _text(row, 7),
        // Vacía en los formatos 1 y 2, y en los movimientos sueltos.
        debtId: _intOrNull(row, 8),
      ));
    }
    return transactions;
  }

  List<DebtModel> parseDebts(List<List<dynamic>> rows) {
    if (rows.isEmpty) return const [];
    _checkHeader(rows.first, [_debtHeader], _sheetDebts);

    final debts = <DebtModel>[];
    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (_isBlank(row)) continue;

      final name = _text(row, 1);
      final total = _doubleOrNull(row, 2);
      final installments = _intOrNull(row, 3);
      final firstDate = _dateOrNull(row, 4);
      // Sin estos datos la deuda no se puede mostrar. Sus cuotas sí están
      // completas en movimientos, así que se niega igual que con una
      // fecha ilegible: mejor no tocar nada que restaurar a medias.
      if (name.isEmpty ||
          total == null ||
          installments == null ||
          installments < 1 ||
          firstDate == null) {
        throw SheetsBackupException(
          'La fila ${i + 1} de "$_sheetDebts" está incompleta o ilegible.',
        );
      }

      debts.add(DebtModel(
        id: _intOrNull(row, 0),
        name: name,
        totalAmount: total,
        installments: installments,
        firstDate: firstDate,
      ));
    }
    return debts;
  }

  /// Formato 2: número de serie de Sheets (llega como número gracias a
  /// `UNFORMATTED_VALUE`). Formato 1: texto ISO 8601.
  DateTime? _dateOrNull(List<dynamic> row, int index) {
    if (index >= row.length) return null;
    final cell = row[index];
    if (cell is num) return serialToDate(cell);
    return DateTime.tryParse(_text(row, index));
  }

  MovementType? _typeOrNull(List<dynamic> row, int index) {
    switch (_normalize(_text(row, index))) {
      case 'gasto':
      case 'expense':
        return MovementType.expense;
      case 'ingreso':
      case 'income':
        return MovementType.income;
      default:
        return null;
    }
  }

  /// La planilla es visible y editable en Drive: si alguien le cambió las
  /// columnas, es mejor negarse que restaurar datos corridos de lugar.
  ///
  /// [accepted] trae un encabezado por cada formato que se sabe leer. Se
  /// comparan sin mayúsculas ni tildes, que no cambian qué columna es cuál.
  ///
  /// Cada formato se compara con su propio ancho: el 2 tiene una columna
  /// menos que el 3, y la celda que falta llega vacía.
  void _checkHeader(
      List<dynamic> row, List<List<String>> accepted, String tab) {
    bool matches(List<String> header) {
      for (var i = 0; i < header.length; i++) {
        if (_normalize(_text(row, i)) != _normalize(header[i])) return false;
      }
      return true;
    }

    if (!accepted.any(matches)) {
      throw SheetsBackupException(
        'La hoja "$tab" no tiene las columnas esperadas.',
        detail: 'se esperaba: ${accepted.first.join(', ')}',
      );
    }
  }

  static const Map<String, String> _accents = {
    'á': 'a',
    'é': 'e',
    'í': 'i',
    'ó': 'o',
    'ú': 'u',
  };

  String _normalize(String value) => value
      .trim()
      .toLowerCase()
      .split('')
      .map((char) => _accents[char] ?? char)
      .join();

  bool _isBlank(List<dynamic> row) =>
      row.every((cell) => cell == null || cell.toString().trim().isEmpty);

  String _text(List<dynamic> row, int index) {
    if (index >= row.length) return '';
    return row[index]?.toString().trim() ?? '';
  }

  String _textOr(List<dynamic> row, int index, String fallback) {
    final value = _text(row, index);
    return value.isEmpty ? fallback : value;
  }

  int? _intOrNull(List<dynamic> row, int index) => _doubleOrNull(row, index)?.round();

  int _intOr(List<dynamic> row, int index, int fallback) =>
      _intOrNull(row, index) ?? fallback;

  /// Agrupación de miles con punto, como la escribe el campo de monto de
  /// la app: "1.234", "1.234.567". No matchea "1.5" ni "1.23".
  static final RegExp _esClThousands = RegExp(r'^\d{1,3}(\.\d{3})+$');

  double? _doubleOrNull(List<dynamic> row, int index) {
    if (index >= row.length) return null;
    final cell = row[index];
    if (cell is num) return cell.toDouble();

    // La app escribe los montos como número, así que llegar acá como
    // texto significa que alguien editó la planilla a mano, en es-CL.
    final text = cell?.toString().trim() ?? '';
    if (text.isEmpty) return null;

    if (text.contains(',')) {
      // Con coma presente no hay ambigüedad: la coma decide los
      // decimales y los puntos son separadores de miles ("1.234,5").
      return double.tryParse(text.replaceAll('.', '').replaceAll(',', '.'));
    }
    if (_esClThousands.hasMatch(text)) {
      // "1.234" es mil doscientos treinta y cuatro, no 1,234: en pesos
      // chilenos el punto agrupa miles. Se exige la agrupación exacta
      // para no reinterpretar un decimal legítimo como "1.5".
      return double.tryParse(text.replaceAll('.', ''));
    }
    return double.tryParse(text);
  }

  // ---------- HTTP ----------

  Future<Map<String, dynamic>?> _get(
    Uri uri,
    String token, {
    bool allowNotFound = false,
  }) async {
    final response =
        await _send(() => _client.get(uri, headers: _headers(token)));
    if (allowNotFound && response.statusCode == 404) return null;
    return _decode(response);
  }

  Future<Map<String, dynamic>> _post(Uri uri, String token, Object body) async {
    final response = await _send(() => _client.post(
          uri,
          headers: _headers(token),
          body: jsonEncode(body),
        ));
    return _decode(response) ?? const {};
  }

  Future<Map<String, dynamic>> _patch(
      Uri uri, String token, Object body) async {
    final response = await _send(() => _client.patch(
          uri,
          headers: _headers(token),
          body: jsonEncode(body),
        ));
    return _decode(response) ?? const {};
  }

  Future<http.Response> _send(Future<http.Response> Function() request) async {
    try {
      return await request().timeout(const Duration(seconds: 30));
    } on SheetsBackupException {
      rethrow;
    } catch (e) {
      throw SheetsBackupException(
        'No se pudo conectar con Google.',
        detail: e.toString(),
      );
    }
  }

  Map<String, dynamic>? _decode(http.Response response) {
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw SheetsBackupException(
        'Google rechazó el permiso. Volvé a conectar la cuenta.',
        detail: 'HTTP ${response.statusCode}',
      );
    }
    if (response.statusCode >= 400) {
      throw SheetsBackupException(
        'Google respondió con un error.',
        detail: 'HTTP ${response.statusCode}: ${_errorMessage(response.body)}',
      );
    }
    if (response.body.isEmpty) return null;

    final decoded = jsonDecode(response.body);
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  String _errorMessage(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] is Map) {
        return (decoded['error'] as Map)['message']?.toString() ?? body;
      }
    } catch (_) {
      // Un cuerpo que no es JSON igual sirve como pista tal cual viene.
    }
    return body;
  }
}
