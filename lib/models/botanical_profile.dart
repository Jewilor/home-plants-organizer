/// Сведения об условиях содержания известного вида растения.
class BotanicalProfile {
  const BotanicalProfile({
    required this.name,
    required this.species,
    required this.aliases,
    required this.light,
    required this.humidity,
    required this.source,
    this.sourceName = 'Королевское садоводческое общество',
  });
  final String name, species, light, humidity, source;

  /// Название организации, подготовившей исходные справочные сведения.
  final String sourceName;
  final List<String> aliases;

  /// Преобразует запись локального справочника в модель предметной области.
  factory BotanicalProfile.fromJson(Map<String, dynamic> json) =>
      BotanicalProfile(
        name: json['name'] as String,
        species: json['species'] as String,
        aliases: List<String>.from(json['aliases'] as List),
        light: json['light'] as String,
        humidity: json['humidity'] as String,
        source: json['source'] as String,
        sourceName:
            json['sourceName'] as String? ??
            'Королевское садоводческое общество',
      );
}
