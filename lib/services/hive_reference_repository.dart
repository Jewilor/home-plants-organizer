import 'package:hive_ce/hive.dart';
import '../models/reference_entry.dart';
import 'reference_repository.dart';

/// Хранит семейства и удобрения в отдельных коллекциях Hive CE.
class HiveReferenceRepository implements ReferenceRepository {
  HiveReferenceRepository._(this._families, this._fertilizers, this._metadata);
  final Box<Map> _families;
  final Box<Map> _fertilizers;
  final Box<dynamic> _metadata;

  /// Открывает коллекции и заполняет базовый справочник только при первом запуске.
  static Future<HiveReferenceRepository> open(String directory) async {
    Hive.init(directory);
    final families = await Hive.openBox<Map>('plant_families');
    Box<Map>? fertilizers;
    Box<dynamic>? metadata;
    try {
      fertilizers = await Hive.openBox<Map>('fertilizer_types');
      metadata = await Hive.openBox<dynamic>('reference_metadata');
      final repository = HiveReferenceRepository._(
        families,
        fertilizers,
        metadata,
      );
      if (metadata.get('initialized') != true) {
        await families.putAll({
          'family-aroids': const ReferenceEntry(
            id: 'family-aroids',
            name: 'Ароидные',
            icon: ReferenceIcon.leaf,
          ).toMap(),
          'family-mulberry': const ReferenceEntry(
            id: 'family-mulberry',
            name: 'Тутовые',
            icon: ReferenceIcon.tree,
          ).toMap(),
          'family-asparagus': const ReferenceEntry(
            id: 'family-asparagus',
            name: 'Спаржевые',
            icon: ReferenceIcon.flower,
          ).toMap(),
        });
        await fertilizers.putAll({
          'fertilizer-universal': const ReferenceEntry(
            id: 'fertilizer-universal',
            name: 'Универсальное',
            icon: ReferenceIcon.nutrients,
          ).toMap(),
          'fertilizer-leaves': const ReferenceEntry(
            id: 'fertilizer-leaves',
            name: 'Для декоративно-лиственных растений',
            icon: ReferenceIcon.leaf,
          ).toMap(),
          'fertilizer-flowers': const ReferenceEntry(
            id: 'fertilizer-flowers',
            name: 'Для цветущих растений',
            icon: ReferenceIcon.flower,
          ).toMap(),
        });
        await metadata.put('schema_version', 1);
        await metadata.put('sequence', 0);
        await metadata.put('initialized', true);
      }
      return repository;
    } catch (_) {
      await families.close();
      await fertilizers?.close();
      await metadata?.close();
      rethrow;
    }
  }

  Box<Map> _box(ReferenceKind kind) =>
      kind == ReferenceKind.family ? _families : _fertilizers;
  @override
  Future<List<ReferenceEntry>> load(ReferenceKind kind) async => [
    for (final value in _box(kind).values) ReferenceEntry.fromMap(value),
  ];

  @override
  Future<String> nextId(ReferenceKind kind) async {
    final sequence = _metadata.get('sequence', defaultValue: 0) as int;
    // Сначала резервируем номер: сбой следующей записи не создаст повторный ключ.
    await _metadata.put('sequence', sequence + 1);
    return '${kind.name}-$sequence';
  }

  @override
  Future<void> save(ReferenceKind kind, ReferenceEntry entry) =>
      _box(kind).put(entry.id, entry.toMap());
  @override
  Future<void> delete(ReferenceKind kind, String id) => _box(kind).delete(id);
  @override
  Future<void> close() async {
    if (_families.isOpen) await _families.close();
    if (_fertilizers.isOpen) await _fertilizers.close();
    if (_metadata.isOpen) await _metadata.close();
  }
}
