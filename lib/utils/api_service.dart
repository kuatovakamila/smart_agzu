import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'cache_manager.dart';

class ApiResponse<T> {
  final T data;
  final bool fromCache;
  final int? totalCount;
  final int? currentPage;
  final bool hasMore;

  ApiResponse({
    required this.data,
    required this.fromCache,
    this.totalCount,
    this.currentPage,
    required this.hasMore,
  });
}

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  final CacheManager _cache = CacheManager();
  static const String baseUrl = '';

  // Настройки пагинации
  static const int defaultPageSize = 50;
  static const int maxRetries = 3;
  static const Duration baseRetryDelay = Duration(milliseconds: 500);
  static const int maxConcurrentRequests =
      8; // Увеличил для лучшей производительности

  // Семафор для ограничения параллельных запросов
  final Map<String, bool> _activeRequests = {};

  Future<ApiResponse<List<Map<String, String>>>> fetchAgzuData(
    String agzu,
    int cdng,
    DateTime startDate,
    DateTime endDate, {
    int page = 0,
    int pageSize = defaultPageSize,
    bool useCache = true,
  }) async {
    // Проверяем кэш сначала
    if (useCache) {
      final cachedData = _cache.getAgzuData(agzu, cdng, startDate, endDate,
          page: page, pageSize: pageSize);
      if (cachedData != null) {
        print('📦 Данные для $agzu (страница $page) взяты из кэша');
        return ApiResponse(
          data: cachedData,
          fromCache: true,
          currentPage: page,
          hasMore: cachedData.length ==
              pageSize, // Если полная страница, возможно есть еще
        );
      }
    }

    // Проверяем, не выполняется ли уже запрос для этого АГЗУ
    final requestKey = '${agzu}_${cdng}_${page}';
    if (_activeRequests[requestKey] == true) {
      // Ждем 100мс и проверяем кэш снова
      await Future.delayed(const Duration(milliseconds: 100));
      final cachedData = _cache.getAgzuData(agzu, cdng, startDate, endDate,
          page: page, pageSize: pageSize);
      if (cachedData != null) {
        return ApiResponse(
          data: cachedData,
          fromCache: true,
          currentPage: page,
          hasMore: cachedData.length == pageSize,
        );
      }
    }

    _activeRequests[requestKey] = true;

    try {
      final data =
          await _fetchWithRetry(agzu, cdng, startDate, endDate, page, pageSize);

      // Сохраняем в кэш
      _cache.setAgzuData(agzu, cdng, startDate, endDate, data,
          page: page, pageSize: pageSize);

      print(
          '🌐 Загружено ${data.length} записей для $agzu (страница $page) с сервера');

      return ApiResponse(
        data: data,
        fromCache: false,
        currentPage: page,
        hasMore: data.length == pageSize,
      );
    } finally {
      _activeRequests.remove(requestKey);
    }
  }

  Future<List<Map<String, String>>> _fetchWithRetry(
    String agzu,
    int cdng,
    DateTime startDate,
    DateTime endDate,
    int page,
    int pageSize,
  ) async {
    Exception? lastException;

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        // Добавляем задержку между попытками
        if (attempt > 1) {
          final delay = Duration(
              milliseconds:
                  baseRetryDelay.inMilliseconds * attempt + (page % 3) * 100);
          await Future.delayed(delay);
        }

        final url = Uri.parse(baseUrl).replace(queryParameters: {
          'start_date': DateFormat("yyyy-MM-ddTHH:mm:ss").format(startDate),
          'end_date': DateFormat("yyyy-MM-ddTHH:mm:ss").format(endDate),
          'agzu': agzu,
          'cdng': cdng.toString(),
          'page': page.toString(),
          'page_size': pageSize.toString(),
        });

        final response = await http.get(url).timeout(
              const Duration(seconds: 15),
              onTimeout: () => throw TimeoutException(
                  'Request timeout', const Duration(seconds: 15)),
            );

        if (response.statusCode == 502) {
          throw HttpException('Server overloaded (502)', response.statusCode);
        } else if (response.statusCode == 429) {
          // Rate limit - ждем больше
          throw HttpException('Rate limited (429)', response.statusCode);
        } else if (response.statusCode != 200) {
          throw HttpException(
              'HTTP ${response.statusCode}', response.statusCode);
        }

        final decoded = jsonDecode(response.body);
        final rows = (decoded['rows'] as List?) ?? [];

        if (rows.length <= 1) {
          return []; // Пустые данные
        }

        final headers = rows.first.map((e) => e.toString()).toList();
        final dataRows = rows.skip(1);

        final result = dataRows.map<Map<String, String>>((r) {
          final m = <String, String>{};
          for (int i = 0; i < headers.length && i < r.length; i++) {
            m[headers[i]] = r[i].toString();
          }
          return m;
        }).toList();

        return result;
      } catch (e) {
        lastException = e is Exception ? e : Exception(e.toString());

        if (e is HttpException && e.statusCode == 502 && attempt < maxRetries) {
          print('🔄 $agzu: 502 ошибка, попытка $attempt/$maxRetries');
          continue;
        } else if (e is HttpException &&
            e.statusCode == 429 &&
            attempt < maxRetries) {
          // Rate limit - экспоненциальная задержка
          await Future.delayed(Duration(milliseconds: 1000 * attempt));
          print('⏳ $agzu: Rate limit, ждем ${1000 * attempt}мс');
          continue;
        } else if (e is TimeoutException && attempt < maxRetries) {
          print('⏱️ $agzu: Timeout, попытка $attempt/$maxRetries');
          continue;
        }

        print('❌ $agzu: ${e.toString()} (попытка $attempt/$maxRetries)');
        if (attempt == maxRetries) break;
      }
    }

    throw lastException ?? Exception('Unknown error');
  }

  // Предварительная загрузка следующей страницы
  Future<void> prefetchNextPage(
    String agzu,
    int cdng,
    DateTime startDate,
    DateTime endDate,
    int currentPage,
  ) async {
    final nextPage = currentPage + 1;

    // Проверяем, есть ли уже в кэше
    if (_cache.hasData(agzu, cdng, startDate, endDate, page: nextPage)) {
      return;
    }

    // Запускаем предварительную загрузку в фоне
    unawaited(fetchAgzuData(agzu, cdng, startDate, endDate, page: nextPage));
  }

  // Загрузка всех страниц для АГЗУ (оптимизированная)
  Future<List<Map<String, String>>> fetchAllAgzuData(
    String agzu,
    int cdng,
    DateTime startDate,
    DateTime endDate, {
    void Function(int loadedCount)? onProgress,
  }) async {
    final allData = <Map<String, String>>[];
    int page = 0;
    bool hasMore = true;

    while (hasMore) {
      try {
        final response =
            await fetchAgzuData(agzu, cdng, startDate, endDate, page: page);
        allData.addAll(response.data);
        hasMore = response.hasMore && response.data.isNotEmpty;
        page++;

        onProgress?.call(allData.length);

        // Предварительная загрузка следующей страницы если есть еще данные
        if (hasMore) {
          unawaited(prefetchNextPage(agzu, cdng, startDate, endDate, page));
        }
      } catch (e) {
        print('❌ Ошибка загрузки страницы $page для $agzu: $e');
        break;
      }
    }

    return allData;
  }

  // Очистка кэша
  void clearCache() {
    _cache.clear();
  }

  // Статистика кэша
  Map<String, dynamic> getCacheStats() {
    return _cache.getCacheStats();
  }
}

class HttpException implements Exception {
  final String message;
  final int statusCode;

  HttpException(this.message, this.statusCode);

  @override
  String toString() => message;
}

// Utility function для "fire and forget" операций
void unawaited(Future<void> future) {
  future.catchError((error) {
    print('Background operation failed: $error');
  });
}
