/// Раздел вспомогательного справочника.
enum ReferenceKind { family, fertilizer }

/// Сохраняемые обозначения значков, независимые от Flutter.
enum ReferenceIcon { leaf, tree, flower, nutrients, water, sun }

/// Запись нереляционного справочника с устойчивым идентификатором.
class ReferenceEntry {
  const ReferenceEntry({
    required this.id,
    required this.name,
    required this.icon,
  });
  final String id;
  final String name;
  final ReferenceIcon icon;

  /// Преобразует запись в значения, поддерживаемые Hive.
  Map<String, Object> toMap() => {'id': id, 'name': name, 'icon': icon.name};

  /// Восстанавливает запись из нереляционного хранилища.
  factory ReferenceEntry.fromMap(Map<dynamic, dynamic> map) => ReferenceEntry(
    id: map['id'] as String,
    name: map['name'] as String,
    icon: ReferenceIcon.values.byName(map['icon'] as String),
  );
}
