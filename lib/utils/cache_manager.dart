class CacheEntry<T> {
  final T data;
  final DateTime timestamp;
  final Duration ttl;

  CacheEntry(this.data, this.timestamp, this.ttl);

  bool get isExpired => DateTime.now().difference(timestamp) > ttl;
}

class CacheManager {
  static final CacheManager _instance = CacheManager._internal();
  factory CacheManager() => _instance;
  CacheManager._internal();

  final Map<String, CacheEntry<dynamic>> _cache = {};
  final int _maxCacheSize = 100; // Максимум 100 записей в кэше

  // Кэш для данных АГЗУ с TTL 5 минут
  static const Duration _defaultTTL = Duration(minutes: 5);

  String _generateKey(
      String agzu, int cdng, DateTime startDate, DateTime endDate,
      {int page = 0, int pageSize = 50}) {
    final start = startDate.toIso8601String();
    final end = endDate.toIso8601String();
    return 'agzu_${agzu}_cdng_${cdng}_${start}_${end}_page_${page}_size_$pageSize';
  }

  // Сохранить данные в кэш
  void set<T>(String key, T data, {Duration? ttl}) {
    // Очистка старых записей если кэш переполнен
    if (_cache.length >= _maxCacheSize) {
      _cleanupExpired();
      if (_cache.length >= _maxCacheSize) {
        // Удаляем самые старые записи
        final oldestKeys = _cache.entries
            .where((e) => e.value.isExpired)
            .map((e) => e.key)
            .take(20)
            .toList();
        for (final key in oldestKeys) {
          _cache.remove(key);
        }
      }
    }

    _cache[key] = CacheEntry<T>(data, DateTime.now(), ttl ?? _defaultTTL);
  }

  // Получить данные из кэша
  T? get<T>(String key) {
    final entry = _cache[key];
    if (entry == null || entry.isExpired) {
      _cache.remove(key);
      return null;
    }
    return entry.data as T?;
  }

  // Получить кэшированные данные АГЗУ
  List<Map<String, String>>? getAgzuData(
    String agzu,
    int cdng,
    DateTime startDate,
    DateTime endDate, {
    int page = 0,
    int pageSize = 50,
  }) {
    final key = _generateKey(agzu, cdng, startDate, endDate,
        page: page, pageSize: pageSize);
    return get<List<Map<String, String>>>(key);
  }

  // Сохранить данные АГЗУ в кэш
  void setAgzuData(
    String agzu,
    int cdng,
    DateTime startDate,
    DateTime endDate,
    List<Map<String, String>> data, {
    int page = 0,
    int pageSize = 50,
  }) {
    final key = _generateKey(agzu, cdng, startDate, endDate,
        page: page, pageSize: pageSize);
    set(key, data);
  }

  // Очистка устаревших записей
  void _cleanupExpired() {
    final expiredKeys = _cache.entries
        .where((entry) => entry.value.isExpired)
        .map((entry) => entry.key)
        .toList();

    for (final key in expiredKeys) {
      _cache.remove(key);
    }
  }

  // Очистить весь кэш
  void clear() {
    _cache.clear();
  }

  // Очистить кэш для конкретного АГЗУ
  void clearAgzuData(String agzu) {
    final keysToRemove =
        _cache.keys.where((key) => key.contains('agzu_$agzu')).toList();

    for (final key in keysToRemove) {
      _cache.remove(key);
    }
  }

  // Получить информацию о кэше
  Map<String, dynamic> getCacheStats() {
    _cleanupExpired();
    return {
      'total_entries': _cache.length,
      'max_size': _maxCacheSize,
      'memory_usage_estimate':
          _cache.length * 1024, // Примерная оценка в байтах
    };
  }

  // Проверить есть ли данные в кэше (без извлечения)
  bool hasData(String agzu, int cdng, DateTime startDate, DateTime endDate,
      {int page = 0, int pageSize = 50}) {
    final key = _generateKey(agzu, cdng, startDate, endDate,
        page: page, pageSize: pageSize);
    final entry = _cache[key];
    return entry != null && !entry.isExpired;
  }
}
