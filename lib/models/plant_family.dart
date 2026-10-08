/// Приводит известное научное название семейства к русскому названию справочника.
/// Неизвестные названия сохраняются: семейство не определяется по догадке.
String canonicalFamilyName(String name) {
  final clean = name.trim().replaceAll(RegExp(r'\s+'), ' ');
  return switch (clean.toLowerCase()) {
    'araceae' || 'ароидные' => 'Ароидные',
    'moraceae' || 'тутовые' => 'Тутовые',
    'asparagaceae' || 'спаржевые' => 'Спаржевые',
    _ => clean,
  };
}

/// Ключ сопоставления не зависит от регистра, пробелов и русского либо научного имени.
String familyNameKey(String name) =>
    canonicalFamilyName(name).toLowerCase().replaceAll('ё', 'е');
