import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../models/care_guide.dart';
import '../models/reminder.dart';
import '../models/plant.dart';
import '../models/care_record.dart';
import '../models/garden_snapshot.dart';
import 'garden_repository.dart';

/// Основная реляционная база растений, расписания и выполненного ухода.
class SqliteGardenRepository implements GardenRepository {
  SqliteGardenRepository._(this.database);
  final Database database;
  static const schemaVersion = 4;

  /// Открывает базу и выполняет необходимые миграции схемы.
  static Future<SqliteGardenRepository> open({
    required String path,
    DatabaseFactory? factory,
  }) async {
    final db = await (factory ?? databaseFactory).openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) async {
          await createVersionOne(db);
          if (version >= 2) await upgradeToVersionTwo(db);
          if (version >= 3) await upgradeToVersionThree(db);
          if (version >= 4) await upgradeToVersionFour(db);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) await upgradeToVersionTwo(db);
          if (oldVersion < 3) await upgradeToVersionThree(db);
          if (oldVersion < 4) await upgradeToVersionFour(db);
        },
      ),
    );
    return SqliteGardenRepository._(db);
  }

  /// Создаёт исходную схему. Отдельный метод позволяет проверить миграцию.
  static Future<void> createVersionOne(Database db) async {
    await db.execute('''CREATE TABLE plants (
      id TEXT PRIMARY KEY NOT NULL,
      name TEXT NOT NULL CHECK(length(trim(name)) BETWEEN 1 AND 80),
      species TEXT NOT NULL, room TEXT NOT NULL,
      care_conditions TEXT NOT NULL DEFAULT '', art INTEGER NOT NULL
    )''');
    await db.execute('''CREATE TABLE care_procedures (
      id TEXT PRIMARY KEY NOT NULL,
      plant_id TEXT NOT NULL REFERENCES plants(id) ON DELETE CASCADE,
      date TEXT NOT NULL,
      type TEXT NOT NULL CHECK(type IN ('watering','feeding','repotting')),
      weekly INTEGER NOT NULL CHECK(weekly IN (0,1)), completed_on TEXT
    )''');
    await db.execute('''CREATE TABLE care_records (
      id TEXT PRIMARY KEY NOT NULL,
      plant_id TEXT NOT NULL REFERENCES plants(id) ON DELETE CASCADE,
      type TEXT NOT NULL CHECK(type IN ('watering','feeding','repotting')),
      performed_on TEXT NOT NULL, note TEXT NOT NULL CHECK(length(note) <= 300),
      UNIQUE(plant_id, type, performed_on)
    )''');
    await db.execute('''CREATE TABLE procedure_completions (
      procedure_id TEXT NOT NULL REFERENCES care_procedures(id) ON DELETE CASCADE,
      occurrence_date TEXT NOT NULL, performed_on TEXT NOT NULL,
      PRIMARY KEY(procedure_id, occurrence_date)
    )''');
    await db.execute(
      'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
    );
    await db.execute(
      'CREATE INDEX procedures_by_plant ON care_procedures(plant_id, type)',
    );
    await db.execute(
      'CREATE INDEX records_by_plant ON care_records(plant_id, performed_on DESC)',
    );
  }

  /// Добавляет ссылки на справочники без удаления существующих данных.
  /// Ссылки между SQLite и Hive проверяются моделью состояния, а не SQL.
  static Future<void> upgradeToVersionTwo(Database db) async {
    await db.execute('ALTER TABLE plants ADD COLUMN family_id TEXT');
    await db.execute(
      'ALTER TABLE care_procedures ADD COLUMN fertilizer_id TEXT',
    );
  }

  /// Добавляет сетевые регламенты и произвольный интервал без потери старых данных.
  static Future<void> upgradeToVersionThree(Database db) async {
    await db.execute(
      'ALTER TABLE care_procedures ADD COLUMN repeat_every_days INTEGER NOT NULL DEFAULT 0 CHECK(repeat_every_days BETWEEN 0 AND 365)',
    );
    await db.execute('''CREATE TABLE care_guides (
      plant_id TEXT PRIMARY KEY NOT NULL REFERENCES plants(id) ON DELETE CASCADE,
      guide_json TEXT NOT NULL
    )''');
  }

  /// Дополняет прежние процедуры днями недели и временем без удаления записей.
  static Future<void> upgradeToVersionFour(Database db) async {
    await db.execute(
      "ALTER TABLE care_procedures ADD COLUMN weekdays TEXT NOT NULL DEFAULT '[]'",
    );
    await db.execute(
      "ALTER TABLE care_procedures ADD COLUMN times TEXT NOT NULL DEFAULT '[]'",
    );
    await db.execute(
      "ALTER TABLE care_records ADD COLUMN procedure_id TEXT NOT NULL DEFAULT ''",
    );
    await db.execute('ALTER TABLE care_records ADD COLUMN scheduled_for TEXT');
  }

  @override
  Future<GardenSnapshot?> load() => database.transaction((txn) async {
    final settings = await txn.query('settings');
    final values = {
      for (final row in settings) row['key'] as String: row['value'] as String,
    };
    if (values['initialized'] != '1') return null;
    final plants = await txn.query('plants', orderBy: 'rowid');
    final procedures = await txn.query('care_procedures', orderBy: 'rowid');
    final records = await txn.query(
      'care_records',
      orderBy: 'performed_on DESC, rowid',
    );
    final completed = await txn.query('procedure_completions');
    final guides = await txn.query('care_guides');
    final wateringTimes = values['watering_reminder_times'] == null
        ? <String, dynamic>{}
        : jsonDecode(values['watering_reminder_times']!)
              as Map<String, dynamic>;
    final completions = <String, Map<DateTime, DateTime>>{};
    for (final row in completed) {
      completions.putIfAbsent(
        row['procedure_id'] as String,
        () => {},
      )[DateTime.parse(row['occurrence_date'] as String)] = DateTime.parse(
        row['performed_on'] as String,
      );
    }
    return GardenSnapshot(
      plants: plants.map(
        (row) => Plant(
          id: row['id'] as String,
          name: row['name'] as String,
          species: row['species'] as String,
          room: row['room'] as String,
          careConditions: row['care_conditions'] as String,
          familyId: row['family_id'] as String? ?? '',
          art: row['art'] as int,
        ),
      ),
      procedures: procedures.map(
        (row) => CareProcedure(
          id: row['id'] as String,
          plantId: row['plant_id'] as String,
          date: decodeDay(row['date'] as String),
          type: CareType.values.byName(row['type'] as String),
          weekly: row['weekly'] == 1,
          repeatEveryDays: row['repeat_every_days'] as int,
          weekdays: List<int>.unmodifiable(
            (jsonDecode(row['weekdays'] as String) as List).cast<int>(),
          ),
          times: List<int>.unmodifiable(
            (jsonDecode(row['times'] as String) as List).cast<int>(),
          ),
          completedOn: row['completed_on'] == null
              ? null
              : decodeDay(row['completed_on'] as String),
          fertilizerId: row['fertilizer_id'] as String? ?? '',
        ),
      ),
      records: records.map(
        (row) => CareRecord(
          id: row['id'] as String,
          plantId: row['plant_id'] as String,
          type: CareType.values.byName(row['type'] as String),
          performedOn: DateTime.parse(row['performed_on'] as String),
          procedureId: row['procedure_id'] as String,
          scheduledFor: row['scheduled_for'] == null
              ? null
              : DateTime.parse(row['scheduled_for'] as String),
          note: row['note'] as String,
        ),
      ),
      completions: completions,
      sequence: int.parse(values['sequence'] ?? '0'),
      careGuides: {
        for (final row in guides)
          row['plant_id'] as String: CareGuide.fromJson(
            jsonDecode(row['guide_json'] as String) as Map<String, dynamic>,
          ),
      },
      wateringReminderTimes: {
        for (final entry in wateringTimes.entries)
          entry.key: ReminderTime.fromJson(entry.value as Map<String, dynamic>),
      },
      reminderPreferences: values['reminders'] == null
          ? const ReminderPreferences()
          : ReminderPreferences.fromJson(
              jsonDecode(values['reminders']!) as Map<String, dynamic>,
            ),
    );
  });

  /// Удаляет отсутствующие записи, обновляет существующие и вставляет новые.
  /// UPDATE сохраняет зависимые объекты, в отличие от замены родительской строки.
  Future<void> _syncTable(
    Transaction txn,
    String table,
    List<Map<String, Object?>> rows,
  ) async {
    final existing = (await txn.query(
      table,
      columns: ['id'],
    )).map((row) => row['id'] as String).toSet();
    final wanted = rows.map((row) => row['id'] as String).toSet();
    final batch = txn.batch();
    for (final id in existing.difference(wanted)) {
      batch.delete(table, where: 'id = ?', whereArgs: [id]);
    }
    for (final row in rows) {
      if (existing.contains(row['id'])) {
        batch.update(table, row, where: 'id = ?', whereArgs: [row['id']]);
      } else {
        batch.insert(table, row);
      }
    }
    await batch.commit(noResult: true);
  }

  @override
  Future<void> save(GardenSnapshot snapshot) =>
      database.transaction((txn) async {
        await _syncTable(txn, 'plants', [
          for (final p in snapshot.plants)
            {
              'id': p.id,
              'name': p.name,
              'species': p.species,
              'room': p.room,
              'care_conditions': p.careConditions,
              'art': p.art,
              'family_id': p.familyId.isEmpty ? null : p.familyId,
            },
        ]);
        await _syncTable(txn, 'care_procedures', [
          for (final p in snapshot.procedures)
            {
              'id': p.id,
              'plant_id': p.plantId,
              'date': encodeDay(p.date),
              'type': p.type.name,
              'weekly': p.weekly ? 1 : 0,
              'repeat_every_days': p.repeatEveryDays,
              'weekdays': jsonEncode(p.weekdays),
              'times': jsonEncode(p.times),
              'completed_on': p.completedOn == null
                  ? null
                  : encodeDay(p.completedOn!),
              'fertilizer_id': p.fertilizerId.isEmpty ? null : p.fertilizerId,
            },
        ]);
        await _syncTable(txn, 'care_records', [
          for (final r in snapshot.records)
            {
              'id': r.id,
              'plant_id': r.plantId,
              'type': r.type.name,
              'performed_on': r.performedOn.toIso8601String(),
              'procedure_id': r.procedureId,
              'scheduled_for': r.scheduledFor?.toIso8601String(),
              'note': r.note,
            },
        ]);
        await txn.delete('care_guides');
        for (final entry in snapshot.careGuides.entries) {
          await txn.insert('care_guides', {
            'plant_id': entry.key,
            'guide_json': jsonEncode(entry.value.toJson()),
          });
        }
        await txn.insert('settings', {
          'key': 'reminders',
          'value': jsonEncode(snapshot.reminderPreferences.toJson()),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        await txn.insert('settings', {
          'key': 'watering_reminder_times',
          'value': jsonEncode({
            for (final entry in snapshot.wateringReminderTimes.entries)
              entry.key: entry.value.toJson(),
          }),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        await txn.delete('procedure_completions');
        final batch = txn.batch();
        for (final series in snapshot.completions.entries) {
          for (final occurrence in series.value.entries) {
            batch.insert('procedure_completions', {
              'procedure_id': series.key,
              'occurrence_date': occurrence.key.toIso8601String(),
              'performed_on': occurrence.value.toIso8601String(),
            });
          }
        }
        batch.insert('settings', {
          'key': 'sequence',
          'value': snapshot.sequence.toString(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        batch.insert('settings', {
          'key': 'initialized',
          'value': '1',
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        await batch.commit(noResult: true);
      });

  @override
  Future<void> close() => database.close();
}
