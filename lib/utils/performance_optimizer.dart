import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

class PerformanceOptimizer {
  static final PerformanceOptimizer _instance = PerformanceOptimizer._internal();
  factory PerformanceOptimizer() => _instance;
  PerformanceOptimizer._internal();

  // Пул для переиспользования объектов
  final List<Map<String, String>> _mapPool = [];
  final List<List<dynamic>> _listPool = [];
  
  // Дебаунсинг для UI обновлений
  Timer? _uiUpdateTimer;
  final Map<String, Timer?> _debouncers = {};
  
  // Метрики производительности
  final Map<String, Stopwatch> _stopwatches = {};
  final Map<String, List<int>> _performanceMetrics = {};

  /// Дебаунсинг функций для предотвращения частых вызовов
  void debounce(String key, VoidCallback callback, {Duration delay = const Duration(milliseconds: 100)}) {
    _debouncers[key]?.cancel();
    _debouncers[key] = Timer(delay, callback);
  }

  /// Оптимизированное обновление UI
  void scheduleUIUpdate(VoidCallback callback, {Duration delay = const Duration(milliseconds: 16)}) {
    _uiUpdateTimer?.cancel();
    _uiUpdateTimer = Timer(delay, () {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        callback();
      });
    });
  }

  /// Переиспользование Map объектов
  Map<String, String> getMap() {
    if (_mapPool.isNotEmpty) {
      final map = _mapPool.removeLast();
      map.clear();
      return map;
    }
    return <String, String>{};
  }

  /// Возврат Map в пул
  void returnMap(Map<String, String> map) {
    if (_mapPool.length < 100) { // Ограничиваем размер пула
      map.clear();
      _mapPool.add(map);
    }
  }

  /// Переиспользование List объектов
  List<T> getList<T>() {
    if (_listPool.isNotEmpty) {
      final list = _listPool.removeLast() as List<T>;
      list.clear();
      return list;
    }
    return <T>[];
  }

  /// Возврат List в пул
  void returnList(List<dynamic> list) {
    if (_listPool.length < 50) {
      list.clear();
      _listPool.add(list);
    }
  }

  /// Начать измерение производительности
  void startMeasurement(String key) {
    _stopwatches[key] = Stopwatch()..start();
  }

  /// Завершить измерение и записать результат
  void endMeasurement(String key) {
    final stopwatch = _stopwatches[key];
    if (stopwatch != null) {
      stopwatch.stop();
      final duration = stopwatch.elapsedMilliseconds;
      
      _performanceMetrics.putIfAbsent(key, () => []);
      _performanceMetrics[key]!.add(duration);
      
      // Ограничиваем историю метрик
      if (_performanceMetrics[key]!.length > 100) {
        _performanceMetrics[key]!.removeAt(0);
      }
      
      if (kDebugMode) {
        print('🏎️ Performance [$key]: ${duration}ms');
      }
      
      _stopwatches.remove(key);
    }
  }

  /// Получить среднее время выполнения
  double getAverageTime(String key) {
    final metrics = _performanceMetrics[key];
    if (metrics == null || metrics.isEmpty) return 0.0;
    
    final sum = metrics.reduce((a, b) => a + b);
    return sum / metrics.length;
  }

  /// Получить статистику производительности
  Map<String, dynamic> getPerformanceStats() {
    final stats = <String, dynamic>{};
    
    for (final entry in _performanceMetrics.entries) {
      final key = entry.key;
      final metrics = entry.value;
      
      if (metrics.isNotEmpty) {
        final sum = metrics.reduce((a, b) => a + b);
        final avg = sum / metrics.length;
        final min = metrics.reduce((a, b) => a < b ? a : b);
        final max = metrics.reduce((a, b) => a > b ? a : b);
        
        stats[key] = {
          'average': avg.toStringAsFixed(2),
          'min': min,
          'max': max,
          'count': metrics.length,
        };
      }
    }
    
    return stats;
  }

  /// Оптимизированная обработка больших списков
  Future<List<T>> processLargeList<T>(
    List<T> items,
    T Function(T) processor, {
    int batchSize = 100,
    Duration delay = const Duration(milliseconds: 1),
  }) async {
    final result = getList<T>();
    
    for (int i = 0; i < items.length; i += batchSize) {
      final end = (i + batchSize < items.length) ? i + batchSize : items.length;
      final batch = items.sublist(i, end);
      
      for (final item in batch) {
        result.add(processor(item));
      }
      
      // Даем UI время на обновление
      if (delay.inMicroseconds > 0) {
        await Future.delayed(delay);
      }
    }
    
    return result;
  }

  /// Очистка ресурсов
  void dispose() {
    _uiUpdateTimer?.cancel();
    for (final timer in _debouncers.values) {
      timer?.cancel();
    }
    _debouncers.clear();
    _mapPool.clear();
    _listPool.clear();
    _stopwatches.clear();
    _performanceMetrics.clear();
  }

  /// Логирование производительности
  void logPerformance() {
    if (kDebugMode) {
      print('📊 Статистика производительности:');
      final stats = getPerformanceStats();
      for (final entry in stats.entries) {
        final key = entry.key;
        final data = entry.value;
        print('   $key: avg=${data['average']}ms, min=${data['min']}ms, max=${data['max']}ms, count=${data['count']}');
      }
      print('   🏊‍♂️ Объектные пулы: maps=${_mapPool.length}, lists=${_listPool.length}');
    }
  }
}

/// Миксин для классов, которые хотят использовать оптимизации производительности
mixin PerformanceOptimized {
  PerformanceOptimizer? _optimizer;
  
  PerformanceOptimizer get _safeOptimizer {
    _optimizer ??= PerformanceOptimizer();
    return _optimizer!;
  }
  
  void startPerformanceMeasurement(String key) {
    try {
      _safeOptimizer.startMeasurement(key);
    } catch (e) {
      print('Ошибка startPerformanceMeasurement: $e');
    }
  }
  
  void endPerformanceMeasurement(String key) {
    try {
      _safeOptimizer.endMeasurement(key);
    } catch (e) {
      print('Ошибка endPerformanceMeasurement: $e');
    }
  }
  
  void debounceCall(String key, VoidCallback callback, {Duration delay = const Duration(milliseconds: 100)}) {
    try {
      _safeOptimizer.debounce(key, callback, delay: delay);
    } catch (e) {
      print('Ошибка debounceCall: $e');
      callback();
    }
  }
  
  void scheduleOptimizedUIUpdate(VoidCallback callback) {
    try {
      _safeOptimizer.scheduleUIUpdate(callback);
    } catch (e) {
      print('Ошибка scheduleOptimizedUIUpdate: $e');
      callback();
    }
  }
  
  Map<String, String> getOptimizedMap() {
    try {
      return _safeOptimizer.getMap();
    } catch (e) {
      print('Ошибка getOptimizedMap: $e');
      return <String, String>{};
    }
  }
  
  void returnOptimizedMap(Map<String, String> map) {
    try {
      _safeOptimizer.returnMap(map);
    } catch (e) {
      print('Ошибка returnOptimizedMap: $e');
    }
  }
} 