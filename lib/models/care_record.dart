import 'plant.dart';

/// Фактически выполненная процедура. История не зависит от будущего расписания.
class CareRecord {
  const CareRecord({
    required this.id,
    required this.plantId,
    required this.type,
    required this.performedOn,
    this.note = '',
  });
  final String id;
  final String plantId;
  final CareType type;
  final DateTime performedOn;
  final String note;
}
