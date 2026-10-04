/// Регламент ухода, полученный по сети и сохраняемый отдельно от ручной справки.
class CareGuide {
  const CareGuide({
    required this.species,
    required this.light,
    required this.humidity,
    required this.watering,
    required this.sourceName,
    required this.sourceUrl,
    required this.downloadedAt,
    this.wateringIntervalDays,
  });
  final String species, light, humidity, watering, sourceName, sourceUrl;
  final DateTime downloadedAt;
  final int? wateringIntervalDays;

  /// Проверяет внешние данные до изменения карточки и расписания.
  factory CareGuide.fromJson(Map<String, dynamic> json) {
    String text(String key) {
      final value = json[key];
      if (value is! String || value.trim().isEmpty || value.length > 4000) {
        throw FormatException('Некорректное поле регламента: $key');
      }
      return value.trim();
    }

    final days = json['wateringIntervalDays'];
    if (days != null && (days is! int || days < 1 || days > 365)) {
      throw const FormatException('Некорректный интервал полива.');
    }
    final url = Uri.tryParse(text('sourceUrl'));
    if (url == null ||
        !['http', 'https'].contains(url.scheme) ||
        url.host.isEmpty) {
      throw const FormatException('Некорректный адрес источника.');
    }
    return CareGuide(
      species: text('species'),
      light: text('light'),
      humidity: text('humidity'),
      watering: text('watering'),
      sourceName: text('sourceName'),
      sourceUrl: url.toString(),
      downloadedAt: DateTime.parse(text('downloadedAt')),
      wateringIntervalDays: days as int?,
    );
  }

  /// Преобразует регламент в JSON для долговременного хранения в SQLite.
  Map<String, dynamic> toJson() => {
    'species': species,
    'light': light,
    'humidity': humidity,
    'watering': watering,
    'sourceName': sourceName,
    'sourceUrl': sourceUrl,
    'downloadedAt': downloadedAt.toIso8601String(),
    'wateringIntervalDays': wateringIntervalDays,
  };
}
