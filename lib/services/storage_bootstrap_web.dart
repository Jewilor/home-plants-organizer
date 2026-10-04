import '../viewmodels/garden_view_model.dart';
import 'garden_resources.dart';

/// Веб-демонстрация сохраняет прежние функции; две базы используются на Android.
Future<GardenResources> openGarden({
  String? directoryPath,
  DateTime Function()? clock,
}) async => GardenResources(GardenViewModel(clock: clock));
