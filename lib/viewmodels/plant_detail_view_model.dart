import 'package:flutter/foundation.dart';
import '../models/plant.dart';
import '../models/care_record.dart';
import '../models/botanical_profile.dart';
import '../services/botanical_repository.dart';
import 'garden_view_model.dart';

/// Состояние детального экрана: справка, история и фильтр вида ухода.
class PlantDetailViewModel extends ChangeNotifier {
  PlantDetailViewModel({
    required this.garden,
    required this.plantId,
    required this.repository,
  }) {
    garden.addListener(_changed);
  }
  final GardenViewModel garden;
  final String plantId;
  final BotanicalRepository repository;
  List<BotanicalProfile> _profiles = [];
  bool loading = true;
  bool _disposed = false;
  String? error;
  CareType? filter;
  Plant? get plant {
    for (final p in garden.plants) {
      if (p.id == plantId) return p;
    }
    return null;
  }

  BotanicalProfile? get profile =>
      plant == null ? null : profileFor(_profiles, plant!.species, plant!.name);
  List<CareRecord> get history =>
      garden.records
          .where(
            (r) => r.plantId == plantId && (filter == null || r.type == filter),
          )
          .toList()
        ..sort((a, b) => b.performedOn.compareTo(a.performedOn));

  /// Асинхронно читает справочник, сохраняя состояние загрузки и ошибку.
  Future<void> load() async {
    loading = true;
    error = null;
    _changed();
    try {
      _profiles = await repository.load();
    } catch (_) {
      error = 'Не удалось загрузить ботаническую справку.';
    }
    if (!_disposed) {
      loading = false;
      notifyListeners();
    }
  }

  /// Выбирает вид ухода; значение null показывает полный журнал.
  void selectFilter(CareType? value) {
    filter = value;
    _changed();
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    garden.removeListener(_changed);
    super.dispose();
  }
}
