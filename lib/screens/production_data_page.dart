// production_data_table.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:linked_scroll_controller/linked_scroll_controller.dart';

class ProductionDataTable extends StatefulWidget {
  final String title;
  final List<String> agzuOrder;
  final List<String> columns;
  final Map<String, List<Map<String, String>>> agzuData;
  final int cdng; // <--- добавлено

  const ProductionDataTable({
    super.key,
    required this.title,
    required this.agzuOrder,
    required this.columns,
    required this.agzuData,
    required this.cdng, // <--- добавлено
  });

  @override
  State<ProductionDataTable> createState() => _ProductionDataTableState();
}

class _ProductionDataTableState extends State<ProductionDataTable> {
  // ───────── переводы колонок ─────────
  static const _ru = <String, String>{
    'STARTDATE': 'Дата замера',
    'STARTTIME': 'Время начала',
    'ENDTIME': 'Время окончания',
    'TAPNUM': 'Номер отвода',
    'WELLNUM': 'Номер скважины',
    'REGIME': 'Режим, м³/сут',
    'DEBETLIQUID1': 'Дебит жидкости, м³/сут',
    'GASDEBET': 'Дебит газа, нм³/сут',
    'REGIMEDEFLECT2': 'Отклон. от режима, м³/сут',
    'AVGTEMP1': 'Режим, м³/сут', // <--- добавлено для ЦДНГ2
  };

  static const _agzuCols = {'AGZU', 'AGZU1', 'AGZU_ID'};
  static const _extraHeaderWidth = 60.0;

  // ───────── контроллеры ─────────
  late final LinkedScrollControllerGroup _grp;
  late final ScrollController _hdrCtrl;
  final _rowCtrls = <String, ScrollController>{};
  final ScrollController _vertCtrl = ScrollController();

  late final Map<String, double> _w; // ширина колонок

  // ───────── lifecycle ─────────
  @override
  void initState() {
    super.initState();
    _grp = LinkedScrollControllerGroup();
    _hdrCtrl = _grp.addAndGet();
    _calcWidths();
  }

  @override
  void dispose() {
    _hdrCtrl.dispose();
    _vertCtrl.dispose();
    for (final c in _rowCtrls.values) c.dispose();
    super.dispose();
  }

  // ───────── helpers ─────────
  List<String> get _cols {
    final orig = widget.columns
        .where((c) => !_agzuCols.contains(c.toUpperCase()) && _ru.containsKey(c))
        .toList();
    if (widget.cdng == 2 && orig.contains('AVGTEMP1')) {
      // Для ЦДНГ2 используем AVGTEMP1 вместо REGIME
      return orig.map((c) => c == 'AVGTEMP1' ? 'AVGTEMP1' : c).toList();
    }
    return orig;
  }

  void _calcWidths() {
    _w = {};
    for (final c in _cols) {
      var mw = _tw(_ru[c]!, bold: true);
      for (final list in widget.agzuData.values) {
        for (final r in list) mw = math.max(mw, _tw(r[c] ?? ''));
      }
      _w[c] = mw + _extraHeaderWidth;
    }
  }

  double _tw(String t, {bool bold = false}) => (TextPainter(
        text: TextSpan(
          text: t,
          style: TextStyle(
              fontSize: 12,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout())
          .size
          .width;

  Color? _cellColor(String col, String? v) {
    if (col == 'REGIMEDEFLECT2') {
      final num? n = num.tryParse(v?.replaceAll(',', '.') ?? '');
      if (n != null && n <= -5) return const Color(0xFFFFD1D1);
    }
    return null;
  }

  ScrollController _ctrlFor(String agzu) =>
      _rowCtrls.putIfAbsent(agzu, () => _grp.addAndGet());

  // AGZU_GU69ZU2 → ГУ-69 АГЗУ-2  (и др.)
  String _ruAgzu(String agzu) {
    if (agzu == '(Выделить все)') return agzu;
    final re = RegExp(r'AGZU_([A-Z]+?)(\d+)([A-Z]?)+ZU(\d+)$');
    final m = re.firstMatch(agzu);
    if (m == null) return agzu;

    final ruPrefix = (m[1] == 'GU') ? 'ГУ' : 'ЗУ';
    final num = m[2]!;
    final litEn = m[3] ?? '';
    final litRu = _latinToCyr(litEn);
    final agzuNum = m[4]!;

    final left = litRu.isEmpty ? '$ruPrefix-$num' : '$ruPrefix-$num$litRu';
    return '$left АГЗУ-$agzuNum';
  }

  String _latinToCyr(String l) => switch (l) {
        'A' => 'А',
        'B' => 'Б',
        'C' => 'С',
        'D' => 'Д',
        'E' => 'Е',
        _ => l,
      };

  // ───────── UI ─────────
  @override
  Widget build(BuildContext ctx) {
    final cols = _cols;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── заголовок отчёта ──
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF1976D2),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: Text(widget.title,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w600)),
          ),
        ),
        const SizedBox(height: 12),

        // ── таблица ──
        Expanded(
          child: Stack(
            children: [
              // вертикальный скролл секций
              Padding(
                padding: const EdgeInsets.only(top: 56),
                child: ListView.builder(
                  controller: _vertCtrl,
                  itemCount: widget.agzuOrder.length,
                  itemBuilder: (ctx, i) {
                    final id = widget.agzuOrder[i];
                    final rows = widget.agzuData[id] ?? [];
                    final rc = _ctrlFor(id);

                    return Column(
                      key: ValueKey(id), // ← фикс: уникальный ключ
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // название AGЗУ
                        Container(
                          width: MediaQuery.of(ctx).size.width,
                          color: const Color(0xFFE0E0E0),
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Center(
                            child: Text(_ruAgzu(id),
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 13)),
                          ),
                        ),
                        // строки
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          controller: rc,
                          child: Column(
                            children: rows
                                .map((r) => Row(
                                      children: cols
                                          .map((c) => Container(
                                                width: _w[c]!,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        vertical: 6,
                                                        horizontal: 4),
                                                alignment: Alignment.center,
                                                decoration: BoxDecoration(
                                                  color: _cellColor(c, r[c]) ??
                                                      Colors.transparent,
                                                  border: const Border(
                                                    right: BorderSide(
                                                        color:
                                                            Color(0xFFE0E0E0)),
                                                    bottom: BorderSide(
                                                        color:
                                                            Color(0xFFE0E0E0)),
                                                  ),
                                                ),
                                                child: Text(
                                                  // --- кастомная логика для 'Режим, м³/сут' ---
                                                  (c == 'REGIME' || c == 'AVGTEMP1') && _ru[c] == 'Режим, м³/сут'
                                                      ? (widget.cdng == 1
                                                          ? (r['REGIME'] ?? '')
                                                          : widget.cdng == 2
                                                              ? (r['AVGTEMP1'] ?? '')
                                                              : (r[c] ?? ''))
                                                      : (r[c] ?? ''),
                                                  style: const TextStyle(fontSize: 12),
                                                  textAlign: TextAlign.center,
                                                ),
                                              ))
                                          .toList(),
                                    ))
                                .toList(),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),

              // шапка
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  controller: _hdrCtrl,
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Color(0xFFE3F2FD),
                      border:
                          Border(bottom: BorderSide(color: Color(0xFFC7C7C7))),
                    ),
                    child: Row(
                      children: cols
                          .map((c) => Container(
                                width: _w[c]!,
                                padding: const EdgeInsets.symmetric(
                                    vertical: 16, horizontal: 4),
                                alignment: Alignment.center,
                                decoration: const BoxDecoration(
                                  border: Border(
                                      right:
                                          BorderSide(color: Color(0xFFC7C7C7))),
                                ),
                                child: Text(_ru[c]!,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13),
                                    textAlign: TextAlign.center),
                              ))
                          .toList(),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
