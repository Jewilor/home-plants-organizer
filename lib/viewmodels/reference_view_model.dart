import 'package:flutter/foundation.dart';
import '../models/reference_entry.dart';
import '../services/reference_repository.dart';

/// Управляет редактированием справочников и проверяет использование их записей.
class ReferenceViewModel extends ChangeNotifier {
  ReferenceViewModel._(this.repository, this._families, this._fertilizers);
  final ReferenceRepository repository;
  final List<ReferenceEntry> _families;
  final List<ReferenceEntry> _fertilizers;
  bool saving = false;
  bool _disposed = false;
  bool Function(ReferenceKind, String)? _inUse;
  static Future<ReferenceViewModel> load(
    ReferenceRepository repository,
  ) async => ReferenceViewModel._(
    repository,
    await repository.load(ReferenceKind.family),
    await repository.load(ReferenceKind.fertilizer),
  );

  /// Устанавливает проверку ссылок из основной базы данных.
  void bindUsageCheck(bool Function(ReferenceKind, String)? check) =>
      _inUse = check;
  List<ReferenceEntry> entries(ReferenceKind kind) => List.unmodifiable(
    (List<ReferenceEntry>.of(
      kind == ReferenceKind.family ? _families : _fertilizers,
    )..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()))),
  );
  ReferenceEntry? find(ReferenceKind kind, String id) {
    for (final entry in entries(kind)) {
      if (entry.id == id) return entry;
    }
    return null;
  }

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  /// Сохраняет запись на устройстве до обновления отображаемого списка.
  Future<String> saveEntry({
    required ReferenceKind kind,
    String? id,
    required String name,
    required ReferenceIcon icon,
  }) async {
    if (saving) throw ArgumentError('Дождитесь сохранения справочника.');
    final clean = name.trim();
    if (clean.isEmpty || clean.length > 80) {
      throw ArgumentError('Введите название от 1 до 80 символов.');
    }
    if (id != null && find(kind, id) == null) {
      throw ArgumentError('Запись уже удалена.');
    }
    if (entries(kind).any(
      (entry) =>
          entry.id != id && entry.name.toLowerCase() == clean.toLowerCase(),
    )) {
      throw ArgumentError('Такое название уже есть в справочнике.');
    }
    saving = true;
    _emit();
    try {
      final entry = ReferenceEntry(
        id: id ?? await repository.nextId(kind),
        name: clean,
        icon: icon,
      );
      await repository.save(kind, entry);
      final list = kind == ReferenceKind.family ? _families : _fertilizers;
      final index = list.indexWhere((item) => item.id == entry.id);
      if (index < 0) {
        list.add(entry);
      } else {
        list[index] = entry;
      }
      return entry.id;
    } finally {
      saving = false;
      _emit();
    }
  }

  /// Не позволяет удалить семейство или удобрение, пока на него ссылается сад.
  Future<void> deleteEntry(ReferenceKind kind, String id) async {
    if (saving) throw ArgumentError('Дождитесь сохранения справочника.');
    if (_inUse?.call(kind, id) ?? false) {
      throw ArgumentError(
        'Запись используется. Сначала измените семейство растения или удобрение в расписании.',
      );
    }
    saving = true;
    _emit();
    try {
      await repository.delete(kind, id);
      (kind == ReferenceKind.family ? _families : _fertilizers).removeWhere(
        (entry) => entry.id == id,
      );
    } finally {
      saving = false;
      _emit();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _inUse = null;
    super.dispose();
  }
}
