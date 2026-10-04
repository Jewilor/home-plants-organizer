import '../models/garden_snapshot.dart';

/// Контракт постоянного хранения сада, независимый от экранов приложения.
abstract interface class GardenRepository {
  /// Возвращает null только до первоначального заполнения базы.
  Future<GardenSnapshot?> load();

  /// Атомарно сохраняет растения, расписание, журнал и отметки выполнения.
  Future<void> save(GardenSnapshot snapshot);

  /// Освобождает соединение с хранилищем.
  Future<void> close();
}
