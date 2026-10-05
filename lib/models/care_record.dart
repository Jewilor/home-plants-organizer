import 'plant.dart';

/// Фактически выполненная процедура. История не зависит от будущего расписания.
class CareRecord {
  const CareRecord({
    required this.id,
    required this.plantId,
    required this.type,
    required this.performedOn,
    this.note = '',
    this.procedureId = '',
    this.scheduledFor,
  });
  final String id;
  final String plantId;
  final CareType type;
  final DateTime performedOn;
  final String note;

  /// Связь с отдельным событием позволяет отменить только его выполнение.
  final String procedureId;
  final DateTime? scheduledFor;
}
