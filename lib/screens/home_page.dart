import 'dart:async';
import 'dart:collection';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'production_data_page.dart';
import '../constants.dart'
    show cdng1Order, cdng2Order, cdng3Order, cdng4Order, sortRowsByAgzuOrder;
import '../utils/api_service.dart';
import '../utils/performance_optimizer.dart';

// Класс для ограничения количества параллельных операций (теперь заменен на ApiService)
class Semaphore {
  final int maxCount;
  int _currentCount;
  final Queue<Completer<void>> _waitQueue = Queue<Completer<void>>();

  Semaphore(this.maxCount) : _currentCount = maxCount;

  Future<void> acquire() async {
    if (_currentCount > 0) {
      _currentCount--;
      return;
    }

    final completer = Completer<void>();
    _waitQueue.add(completer);
    return completer.future;
  }

  void release() {
    if (_waitQueue.isNotEmpty) {
      final completer = _waitQueue.removeFirst();
      completer.complete();
    } else {
      _currentCount++;
    }
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with PerformanceOptimized {
  int selectedCdng = 1; // 1, 2, 3, 4

  // Используем новый ApiService
  final ApiService _apiService = ApiService();

  // Новые настройки для оптимизированной загрузки
  static const int maxConcurrentRequests = 2; // ещё меньше параллелизма
  static const Duration requestDelay =
      Duration(seconds: 1); // пауза между запросами

  // Пауза перед повторной попыткой при ошибке 502

  int totalServerErrors = 0;
  bool _isBatchLoading = false;
  List<Completer> _activeLoads = [];

  // Отменяем все активные загрузки
  void _cancelActiveLoads() {
    for (var completer in _activeLoads) {
      if (!completer.isCompleted) {
        completer.complete();
      }
    }
    _activeLoads.clear();
    loadingAgzus.clear();
    _isBatchLoading = false;
  }

  // Получаем список АГЗУ для выбранного ЦДНГ
  List<String> get cdngAgzuList {
    switch (selectedCdng) {
      case 1:
        return cdng1Order;
      case 2:
        return cdng2Order;
      case 3:
        return cdng3Order;
      case 4:
        return cdng4Order;
      default:
        return cdng1Order;
    }
  }

  // Для дропдауна — сортируем только реально существующие AGZU
  List<String> get agzuList {
    return ['(Выделить все)', ...cdngAgzuList];
  }

  void _showMultiAgzuPicker() {
    showCupertinoModalPopup(
      context: context,
      builder: (_) => Container(
        height: 400,
        color: CupertinoColors.systemBackground.resolveFrom(context),
        child: Column(
          children: [
            const Divider(height: 1),
            Expanded(
              child: StatefulBuilder(
                builder: (context, localSetState) {
                  final isAllSelected =
                      selectedAgzus.length == agzuList.length - 1;

                  return ListView.builder(
                    itemCount: agzuList.length,
                    itemBuilder: (context, index) {
                      final agzu = agzuList[index];
                      final isSelected = agzu == '(Выделить все)'
                          ? isAllSelected
                          : selectedAgzus.contains(agzu);

                      return GestureDetector(
                        onTap: () {
                          if (agzu == '(Выделить все)') {
                            selectedAgzus = isAllSelected
                                ? []
                                : List.from(
                                    agzuList
                                        .where((e) => e != '(Выделить все)'),
                                  );
                          } else {
                            isSelected
                                ? selectedAgzus.remove(agzu)
                                : selectedAgzus.add(agzu);
                          }

                          setState(() {});
                          localSetState(() {});
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                          color: CupertinoColors.systemBackground,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  _humanizeAgzu(agzu),
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.normal,
                                    color: CupertinoColors.label,
                                    decoration: TextDecoration.none,
                                  ),
                                ),
                              ),
                              Icon(
                                isSelected
                                    ? CupertinoIcons.check_mark_circled_solid
                                    : CupertinoIcons.circle,
                                color: const Color.fromARGB(255, 0, 97, 176),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            CupertinoButton(
              child: const Text(
                'Готово',
                style: TextStyle(color: Color.fromARGB(255, 0, 97, 176)),
              ),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }

  DateTime? startDate = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    DateTime.now().day,
    7,
    0,
    0,
  );

  DateTime? endDate = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    DateTime.now().day,
    23,
    59,
    59,
  );

  List<String> selectedAgzus = [];
  Map<String, List<Map<String, String>>> agzuData = {};
  Set<String> loadingAgzus = {};
  List<String>? productionHeaders;
  List<Map<String, String>> productionData = [];
  bool reportRequested = false;

  // Счетчики для статистики
  int totalItemsLoaded = 0;
  int totalFromCache = 0;

  // Контроль частоты обновлений UI
  DateTime _lastUIUpdate = DateTime.now();
  static const Duration _minUIUpdateInterval = Duration(seconds: 2);

  @override
  void initState() {
    super.initState();
    // Инициализируем с выбранными всеми АГЗУ для текущего ЦДНГ
    try {
      selectedAgzus = List<String>.from(cdngAgzuList);
    } catch (e) {
      print('Ошибка инициализации selectedAgzus: $e');
      selectedAgzus = [];
    }
  }

  // Новая оптимизированная функция загрузки данных
  Future<void> fetchData() async {
    if (startDate == null || endDate == null || selectedAgzus.isEmpty) return;

    // Отменяем предыдущие загрузки
    _cancelActiveLoads();

    try {
      startPerformanceMeasurement('full_data_load');
    } catch (e) {
      print('Ошибка startPerformanceMeasurement: $e');
    }

    setState(() {
      reportRequested = false; // скрываем таблицу во время загрузки
      agzuData.clear();
      productionData.clear();
      totalServerErrors = 0;
      totalItemsLoaded = 0;
      totalFromCache = 0;
      _isBatchLoading = true;
    });

    print('🚀 Начинаем загрузку данных для ${selectedAgzus.length} АГЗУ');

    // Используем семафор для ограничения параллельных запросов
    final semaphore = Semaphore(maxConcurrentRequests);
    final futures = selectedAgzus.map((agzu) async {
      await semaphore.acquire();
      try {
        final completer = Completer();
        _activeLoads.add(completer);
        await loadAgzuDataOptimized(agzu, completer);
        // Небольшая пауза, чтобы не создавать всплеск запросов
        await Future.delayed(requestDelay);
      } finally {
        semaphore.release();
      }
    });

    await Future.wait(futures);

    setState(() {
      _isBatchLoading = false;
      reportRequested = true; // показываем таблицу после загрузки
    });

    try {
      endPerformanceMeasurement('full_data_load');
    } catch (e) {
      print('Ошибка endPerformanceMeasurement: $e');
    }

    // Показываем статистику
    final cacheStats = _apiService.getCacheStats();
    print('📊 Загрузка завершена:');
    print('   📦 Всего записей: $totalItemsLoaded');
    print('   🏠 Из кэша: $totalFromCache');
    print('   🌐 С сервера: ${totalItemsLoaded - totalFromCache}');
    print('   💾 Кэш: ${cacheStats['total_entries']} записей');

    // Показываем метрики производительности
    try {
      PerformanceOptimizer().logPerformance();
    } catch (e) {
      print('Ошибка logPerformance: $e');
    }

    // Дополнительный финальный setState через небольшую паузу для стабилизации
    Timer(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() {
          // Финальное обновление для стабилизации таблицы
        });
        print('🏁 Финальное обновление UI завершено');
      }
    });
  }

  // Оптимизированная загрузка данных АГЗУ с кэшированием
  Future<void> loadAgzuDataOptimized(String agzu, Completer cancelToken) async {
    if (!mounted || cancelToken.isCompleted) return;

    try {
      startPerformanceMeasurement('load_$agzu');
    } catch (e) {
      print('Ошибка startPerformanceMeasurement для $agzu: $e');
    }

    setState(() {
      loadingAgzus.add(agzu);
    });

    try {
      // Используем новый ApiService для загрузки всех данных АГЗУ
      final allData = await _apiService.fetchAllAgzuData(
        agzu,
        selectedCdng,
        startDate!,
        endDate!,
        onProgress: (loadedCount) {
          if (mounted && !cancelToken.isCompleted) {
            totalItemsLoaded += loadedCount - (agzuData[agzu]?.length ?? 0);
            // НЕ дебаунсим обновления UI - это создает много прыжков
          }
        },
      );

      // Устанавливаем заголовки, если их еще нет
      if (productionHeaders == null && allData.isNotEmpty) {
        productionHeaders = allData.first.keys.toList();
      }

      // Сортируем данные
      final sortedData = sortRowsByAgzuOrder(allData);
      agzuData[agzu] = sortedData;

      totalItemsLoaded += sortedData.length;

      print('✅ Загружено ${sortedData.length} записей для $agzu');

      // НЕ обновляем UI после каждого АГЗУ - только группами!
    } catch (e) {
      print('❌ Ошибка загрузки данных для $agzu: $e');
      if (!agzuData.containsKey(agzu)) {
        agzuData[agzu] = [];
      }
    } finally {
      if (mounted && !cancelToken.isCompleted) {
        setState(() {
          loadingAgzus.remove(agzu);
        });
      }
      try {
        endPerformanceMeasurement('load_$agzu');
      } catch (e) {
        print('Ошибка endPerformanceMeasurement для $agzu: $e');
      }

      // Групповое обновление UI: только если это последний загружаемый АГЗУ или раз в 3 секунды
      if (loadingAgzus.isEmpty ||
          DateTime.now().difference(_lastUIUpdate).inSeconds >= 3) {
        if (mounted) {
          try {
            scheduleOptimizedUIUpdate(() {
              if (mounted) setState(() {});
            });
          } catch (e) {
            print('Ошибка scheduleOptimizedUIUpdate: $e');
            if (mounted) setState(() {});
          }
          _lastUIUpdate = DateTime.now();
        }
      }
    }
  }

  // Оставляем старую функцию для совместимости (теперь не используется)
  Future<void> loadAgzuData(String agzu) async {
    final completer = Completer();
    _activeLoads.add(completer);
    await loadAgzuDataOptimized(agzu, completer);
  }

  String _humanizeAgzu(String agzu) {
    if (agzu == null || agzu.isEmpty) return 'Неизвестное АГЗУ';
    if (agzu == '(Выделить все)') return agzu;

    // Преобразуем AGZU_GU39ZU1 в ГУ-39 АГЗУ-1
    final regex = RegExp(r'AGZU_([A-Z]+)(\d+)ZU(\d+)');
    final match = regex.firstMatch(agzu);

    if (match != null) {
      final prefix = match.group(1); // GU, ZU, etc.
      final number = match.group(2); // 39
      final zuNumber = match.group(3); // 1

      return '$prefix-$number АГЗУ-$zuNumber';
    }

    return agzu;
  }

  // Функция для очистки кэша
  void _clearCache() {
    _apiService.clearCache();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Кэш очищен'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  // Обновляем обработчик выбора ЦДНГ
  void _onCdngSelected(int cdng) {
    // Отменяем текущие загрузки перед сменой ЦДНГ
    _cancelActiveLoads();

    setState(() {
      selectedCdng = cdng;
      reportRequested = false;
      agzuData.clear();
      productionData.clear();
      try {
        selectedAgzus = List<String>.from(cdngAgzuList);
      } catch (e) {
        print('Ошибка при выборе ЦДНГ: $e');
        selectedAgzus = [];
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Отчеты',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        backgroundColor: const Color.fromARGB(255, 0, 97, 176),
        actions: [
          // Кнопка очистки кэша
          IconButton(
            icon: const Icon(Icons.clear_all, color: Colors.white),
            tooltip: 'Очистить кэш',
            onPressed: _clearCache,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Заголовок с иконкой и статистикой
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    Color.fromARGB(255, 0, 97, 176),
                    Color.fromARGB(255, 0, 120, 215)
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color:
                        const Color.fromARGB(255, 0, 97, 176).withOpacity(0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.analytics_outlined,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Отчет АГЗУ ПУ КМГ',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: Colors.white.withOpacity(0.9),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'ЦДНГ-$selectedCdng',
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Кнопки выбора ЦДНГ
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Выберите ЦДНГ:',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color.fromARGB(255, 50, 50, 50),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (var cdng in [1, 2, 3, 4])
                          Padding(
                            padding: const EdgeInsets.only(right: 12.0),
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: selectedCdng == cdng
                                    ? const Color.fromARGB(255, 0, 97, 176)
                                    : Colors.grey[100],
                                foregroundColor: selectedCdng == cdng
                                    ? Colors.white
                                    : const Color.fromARGB(255, 80, 80, 80),
                                elevation: selectedCdng == cdng ? 4 : 0,
                                shadowColor: selectedCdng == cdng
                                    ? const Color.fromARGB(255, 0, 97, 176)
                                        .withOpacity(0.3)
                                    : Colors.transparent,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(24),
                                ),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 28, vertical: 14),
                                splashFactory: InkRipple.splashFactory,
                              ),
                              onPressed: () {
                                _onCdngSelected(cdng);
                              },
                              child: Text(
                                'ЦДНГ-$cdng',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: selectedCdng == cdng
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Выбор дат
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Период отчета:',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color.fromARGB(255, 50, 50, 50),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TappableDateContainerCupertino(
                          label: 'Начало',
                          initial: startDate,
                          onDateSelected: (date) =>
                              setState(() => startDate = date),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TappableDateContainerCupertino(
                          label: 'Окончание',
                          initial: endDate,
                          onDateSelected: (date) =>
                              setState(() => endDate = date),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Выбор АГЗУ
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Выбор АГЗУ:',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color.fromARGB(255, 50, 50, 50),
                    ),
                  ),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: _showMultiAgzuPicker,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[200]!),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.checklist,
                            color: const Color.fromARGB(255, 0, 97, 176),
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              selectedAgzus.length == agzuList.length - 1
                                  ? 'Выбраны все АГЗУ'
                                  : selectedAgzus.isEmpty
                                      ? 'Не выбрано ни одного АГЗУ'
                                      : 'Выбрано: ${selectedAgzus.length} АГЗУ',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: Color.fromARGB(255, 80, 80, 80),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const Icon(
                            CupertinoIcons.chevron_down,
                            size: 18,
                            color: Color.fromARGB(255, 0, 97, 176),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Кнопка получения отчета
            Container(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color.fromARGB(255, 0, 97, 176),
                  foregroundColor: Colors.white,
                  elevation: 4,
                  shadowColor:
                      const Color.fromARGB(255, 0, 97, 176).withOpacity(0.3),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: _isBatchLoading ? null : fetchData,
                child: _isBatchLoading
                    ? const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          ),
                          SizedBox(width: 12),
                          Text(
                            'Загрузка...',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(width: 8),
                          Text(
                            'Получить отчет',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 24),

            // Таблица данных - показываем только после запроса отчета
            if (reportRequested)
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: SizedBox(
                  height: 780,
                  child: ProductionDataTable(
                    cdng: selectedCdng,
                    title: selectedAgzus.isEmpty
                        ? 'Отчёт: ничего не выбрано'
                        : selectedAgzus.length == cdngAgzuList.length
                            ? 'Отчёт: выбраны все '
                            : 'Отчёт: выбрано ${selectedAgzus.length} ',
                    agzuOrder: selectedAgzus,
                    columns: productionHeaders ??
                        [
                          'STARTDATE',
                          'STARTTIME',
                          'ENDTIME',
                          'TAPNUM',
                          'WELLNUM',
                          'REGIME',
                          'DEBETLIQUID1',
                          'GASDEBET',
                          'REGIMEDEFLECT2'
                        ],
                    agzuData: agzuData,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class TappableDateContainerCupertino extends StatefulWidget {
  final String label;
  final void Function(DateTime)? onDateSelected;
  final DateTime? initial;

  const TappableDateContainerCupertino({
    super.key,
    required this.label,
    this.onDateSelected,
    this.initial,
  });

  @override
  State<TappableDateContainerCupertino> createState() =>
      _TappableDateContainerCupertinoState();
}

class _TappableDateContainerCupertinoState
    extends State<TappableDateContainerCupertino> {
  DateTime? selectedDateTime;

  @override
  void initState() {
    super.initState();
    selectedDateTime = widget.initial;
  }

  void _showCupertinoDateTimePicker() {
    showCupertinoModalPopup(
      context: context,
      builder: (_) => Container(
        height: 280,
        color: CupertinoColors.systemBackground.resolveFrom(context),
        child: Column(
          children: [
            const Divider(height: 1),
            Expanded(
              child: CupertinoDatePicker(
                initialDateTime: selectedDateTime ?? DateTime.now(),
                mode: CupertinoDatePickerMode.dateAndTime,
                use24hFormat: true,
                onDateTimeChanged: (dateTime) {
                  selectedDateTime = dateTime;
                  widget.onDateSelected?.call(dateTime);
                },
              ),
            ),
            CupertinoButton(
              child: const Text('Готово'),
              onPressed: () {
                Navigator.of(context).pop();
                setState(() {});
              },
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dateTime) {
    return DateFormat('dd.MM.yyyy HH:mm').format(dateTime);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _showCupertinoDateTimePicker,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.calendar_today_outlined,
                  size: 16,
                  color: const Color.fromARGB(255, 0, 97, 176),
                ),
                const SizedBox(width: 8),
                Text(
                  widget.label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color.fromARGB(255, 100, 100, 100),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              selectedDateTime == null
                  ? 'Выберите дату'
                  : _formatDate(selectedDateTime!),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color.fromARGB(255, 50, 50, 50),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
