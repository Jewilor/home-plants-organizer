import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/botanical_profile.dart';

/// Контракт локального справочника. Позволяет подменить источник в проверках.
abstract interface class BotanicalRepository {
  Future<List<BotanicalProfile>> load();
}

/// Загружает справочные сведения из включённого в приложение файла JSON.
class AssetBotanicalRepository implements BotanicalRepository {
  Future<List<BotanicalProfile>>? _cached;
  @override
  Future<List<BotanicalProfile>> load() => _cached ??= _read();
  Future<List<BotanicalProfile>> _read() async {
    late String text;
    try {
      text = await rootBundle.loadString('assets/botanical_profiles.json');
    } catch (_) {
      _cached = null;
      rethrow;
    }
    return (jsonDecode(text) as List)
        .map((item) => BotanicalProfile.fromJson(item as Map<String, dynamic>))
        .toList();
  }
}

/// Находит вид по точному названию или ботаническому имени, без угадывания ухода.
BotanicalProfile? profileFor(
  List<BotanicalProfile> profiles,
  String species,
  String name,
) {
  for (final query in [species, name]) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) continue;
    for (final profile in profiles) {
      if (profile.aliases.any((alias) => alias.toLowerCase() == normalized)) {
        return profile;
      }
    }
  }
  return null;
}
