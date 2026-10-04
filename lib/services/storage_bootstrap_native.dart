import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import '../viewmodels/garden_view_model.dart';
import '../viewmodels/reference_view_model.dart';
import 'garden_resources.dart';
import 'sqlite_garden_repository.dart';
import 'hive_reference_repository.dart';
import 'android_reminder_service.dart';
import 'plant_encyclopedia.dart';
import 'reminder_service.dart';

/// Открывает обе базы перед показом сада и сохраняет начальные записи один раз.
Future<GardenResources> openGarden({
  String? directoryPath,
  DateTime Function()? clock,
  bool platformFeatures = true,
}) async {
  final directory = directoryPath == null
      ? await getApplicationSupportDirectory()
      : Directory(directoryPath);
  await directory.create(recursive: true);
  final repository = await SqliteGardenRepository.open(
    path: path.join(directory.path, 'garden.sqlite'),
  );
  HiveReferenceRepository? referenceRepository;
  ReferenceViewModel? references;
  GardenViewModel? garden;
  try {
    final catalogDirectory = Directory(
      path.join(directory.path, 'reference_catalog'),
    );
    await catalogDirectory.create(recursive: true);
    referenceRepository = await HiveReferenceRepository.open(
      catalogDirectory.path,
    );
    references = await ReferenceViewModel.load(referenceRepository);
    final saved = await repository.load();
    ReminderService? reminderService;
    String? notificationIssue;
    if (platformFeatures) {
      try {
        reminderService = await AndroidReminderService.open();
      } catch (_) {
        notificationIssue =
            'Системные напоминания недоступны. Перезапустите приложение для повторной инициализации.';
      }
    }
    garden = GardenViewModel(
      repository: repository,
      references: references,
      snapshot: saved,
      clock: clock,
      encyclopedia: HttpPlantEncyclopedia.configured(),
      reminderService: reminderService,
    );
    if (saved == null) await garden.persist();
    garden.notificationIssue = notificationIssue;
    await garden.refreshReminders();
    return GardenResources(
      garden,
      references: references,
      gardenRepository: repository,
      referenceRepository: referenceRepository,
    );
  } catch (_) {
    garden?.dispose();
    references?.dispose();
    await repository.close();
    await referenceRepository?.close();
    rethrow;
  }
}
