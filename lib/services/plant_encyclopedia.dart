import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/care_guide.dart';

/// Ошибка сетевого поиска с понятным русским сообщением без ключа доступа.
class EncyclopediaException implements Exception {
  const EncyclopediaException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Отделяет асинхронный поиск энциклопедии от интерфейса и базы данных.
abstract interface class PlantEncyclopedia {
  String get sourceLabel;
  Future<CareGuide> fetch(String query);
  void close();
}

/// Получает JSON по HTTP. В учебном режиме данные опубликованы через REST GitHub.
/// Ключ PERENUAL_API_KEY подключает настоящий поиск и детали энциклопедии Perenual.
class HttpPlantEncyclopedia implements PlantEncyclopedia {
  HttpPlantEncyclopedia({
    http.Client? client,
    this.apiKey = '',
    Uri? demoEndpoint,
    this.timeout = const Duration(seconds: 12),
    DateTime Function()? clock,
  }) : _client = client ?? http.Client(),
       _clock = clock ?? DateTime.now,
       demoEndpoint =
           demoEndpoint ??
           Uri.parse(
             'https://api.github.com/repos/Jewilor/home-plants-organizer/contents/demo_api/encyclopedia.json',
           );
  factory HttpPlantEncyclopedia.configured() {
    const key = String.fromEnvironment('PERENUAL_API_KEY');
    const endpoint = String.fromEnvironment('PLANT_API_URL');
    return HttpPlantEncyclopedia(
      apiKey: key,
      demoEndpoint: endpoint.isEmpty ? null : Uri.parse(endpoint),
    );
  }
  final http.Client _client;
  final DateTime Function() _clock;
  final String apiKey;
  final Uri demoEndpoint;
  final Duration timeout;
  @override
  String get sourceLabel =>
      apiKey.isEmpty ? 'Учебная энциклопедия' : 'Perenual';

  /// Проверяет HTTP-статус, срок ожидания и структуру JSON до декодирования модели.
  Future<Map<String, dynamic>> _get(Uri uri) async {
    try {
      final response = await _client
          .get(
            uri,
            headers: {
              'Accept': uri.host == 'api.github.com'
                  ? 'application/vnd.github.raw+json'
                  : 'application/json',
            },
          )
          .timeout(timeout);
      if (response.statusCode == 404) {
        throw const EncyclopediaException(
          'Растение не найдено. Уточните название или вид растения.',
        );
      }
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const EncyclopediaException(
          'Сервис отклонил доступ. Проверьте ключ или лимит запросов.',
        );
      }
      if (response.statusCode == 429) {
        throw const EncyclopediaException(
          'Превышен лимит запросов. Повторите позднее.',
        );
      }
      if (response.statusCode != 200) {
        throw EncyclopediaException(
          'Сервис временно недоступен (код ${response.statusCode}).',
        );
      }
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      return decoded;
    } on TimeoutException {
      throw const EncyclopediaException(
        'Сервис не ответил вовремя. Проверьте соединение и повторите.',
      );
    } on http.ClientException {
      throw const EncyclopediaException(
        'Не удалось подключиться к энциклопедии. Проверьте интернет.',
      );
    } on FormatException {
      throw const EncyclopediaException(
        'Сервис вернул некорректные данные. Регламент не изменён.',
      );
    }
  }

  @override
  Future<CareGuide> fetch(String query) async {
    final clean = query.trim();
    if (clean.isEmpty || clean.length > 100) {
      throw const EncyclopediaException(
        'Введите название или вид растения длиной до 100 символов.',
      );
    }
    try {
      if (apiKey.isNotEmpty) return await _perenual(clean);
      final response = await _get(
        demoEndpoint.replace(
          queryParameters: {...demoEndpoint.queryParameters, 'q': clean},
        ),
      );
      final data = response['data'];
      if (data is! List) throw const FormatException();
      final matches = data.whereType<Map<String, dynamic>>().where((row) {
        final aliases = row['aliases'];
        return aliases is List &&
            aliases.any(
              (name) =>
                  name is String &&
                  name.trim().toLowerCase() == clean.toLowerCase(),
            );
      }).toList();
      if (matches.length != 1) {
        throw const EncyclopediaException(
          'Растение не найдено. Уточните название или вид растения.',
        );
      }
      return CareGuide.fromJson({
        ...matches.single,
        'downloadedAt': _clock().toIso8601String(),
      });
    } on FormatException {
      throw const EncyclopediaException(
        'Сервис вернул некорректный регламент. Сохранённые данные не изменены.',
      );
    }
  }

  /// Выполняет поиск по имени, затем запрашивает детали единственного точного совпадения.
  Future<CareGuide> _perenual(String query) async {
    final search = await _get(
      Uri.https('perenual.com', '/api/v2/species-list', {
        'key': apiKey,
        'q': query,
      }),
    );
    final data = search['data'];
    if (data is! List) throw const FormatException();
    List<dynamic> namesOf(dynamic value) {
      if (value == null) return [];
      if (value is! List) throw const FormatException();
      return value;
    }

    final matches = data.whereType<Map<String, dynamic>>().where((row) {
      final names = [
        row['common_name'],
        ...namesOf(row['scientific_name']),
        ...namesOf(row['other_name']),
      ];
      return names.any(
        (name) => name is String && name.toLowerCase() == query.toLowerCase(),
      );
    }).toList();
    if (matches.length != 1 || matches.single['id'] is! int) {
      throw const EncyclopediaException(
        'Нет единственного точного совпадения. Укажите полное ботаническое имя.',
      );
    }
    final details = await _get(
      Uri.https(
        'perenual.com',
        '/api/v2/species/details/${matches.single['id']}',
        {'key': apiKey},
      ),
    );
    final benchmark = details['watering_general_benchmark'];
    int? days;
    String benchmarkText = '';
    if (benchmark is Map && benchmark['unit'] == 'days') {
      benchmarkText = benchmark['value']?.toString() ?? '';
      final numbers = RegExp(
        r'\d+',
      ).allMatches(benchmarkText).map((m) => int.parse(m.group(0)!)).toList();
      if (numbers.isNotEmpty && numbers.last >= 1 && numbers.last <= 365) {
        days = numbers.last;
      }
    }
    String translated(dynamic value, Map<String, String> words) {
      if (value is! String) return 'Сведения не предоставлены сервисом.';
      return words[value.toLowerCase()] ?? value;
    }

    final sunlight = details['sunlight'];
    final light = sunlight is List && sunlight.isNotEmpty
        ? sunlight
              .map(
                (v) => translated(v, {
                  'full sun': 'Прямой солнечный свет',
                  'part shade': 'Полутень',
                  'full shade': 'Тень',
                  'sun-part shade': 'Солнце и полутень',
                }),
              )
              .join('; ')
        : 'Сведения не предоставлены сервисом.';
    final watering = translated(details['watering'], {
      'frequent': 'Частый полив',
      'average': 'Умеренный полив',
      'minimum': 'Редкий полив',
      'none': 'Полив не требуется',
    });
    final names = details['scientific_name'];
    if (names is! List || names.isEmpty || names.first is! String) {
      throw const FormatException();
    }
    return CareGuide.fromJson({
      'species': names.first,
      'light': light,
      'humidity': 'Сведения о влажности воздуха не предоставлены сервисом.',
      'watering':
          '$watering${benchmarkText.isEmpty ? '' : '. Интервал сервиса: $benchmarkText дней.'}',
      'sourceName': 'Perenual',
      'sourceUrl': 'https://perenual.com/docs/api',
      'downloadedAt': _clock().toIso8601String(),
      'wateringIntervalDays': days,
    });
  }

  @override
  void close() => _client.close();
}
