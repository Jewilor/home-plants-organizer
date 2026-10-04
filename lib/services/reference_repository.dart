import '../models/reference_entry.dart';

/// Контракт вспомогательной нереляционной базы данных.
abstract interface class ReferenceRepository {
  Future<List<ReferenceEntry>> load(ReferenceKind kind);
  Future<String> nextId(ReferenceKind kind);
  Future<void> save(ReferenceKind kind, ReferenceEntry entry);
  Future<void> delete(ReferenceKind kind, String id);
  Future<void> close();
}
