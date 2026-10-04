import '../viewmodels/garden_view_model.dart';
import '../viewmodels/reference_view_model.dart';
import 'garden_repository.dart';
import 'reference_repository.dart';

/// Зависимости приложения с единственным владельцем открытых хранилищ.
class GardenResources {
  GardenResources(
    this.garden, {
    this.references,
    this.gardenRepository,
    this.referenceRepository,
  });
  final GardenViewModel garden;
  final ReferenceViewModel? references;
  final GardenRepository? gardenRepository;
  final ReferenceRepository? referenceRepository;

  /// Закрывает соединения после завершения записи и отписки представлений.
  Future<void> close() async {
    try {
      await garden.flush();
    } finally {
      garden.dispose();
      references?.dispose();
      await gardenRepository?.close();
      await referenceRepository?.close();
    }
  }
}
