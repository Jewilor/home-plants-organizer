import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../models/botanical_profile.dart';
import '../services/botanical_repository.dart';
import '../services/label_recognition_service.dart';

/// Состояние распознавания этикетки. Полученное имя требует подтверждения пользователя.
class LabelScanViewModel extends ChangeNotifier {
  LabelScanViewModel({required this.service, required this.repository});
  final LabelRecognitionService service;
  final BotanicalRepository repository;
  bool busy = false;
  bool _disposed = false;
  String suggestion = '';

  /// Ботаническое имя, найденное в тексте этикетки; пусто, если вид не указан.
  String speciesSuggestion = '';
  String? error;
  BotanicalProfile? profile;

  /// Исключает цену и служебные строки, отдавая приоритет известному виду.
  static String suggestName(String raw, List<BotanicalProfile> profiles) {
    final lower = raw.toLowerCase();
    for (final p in profiles) {
      if (lower.contains(p.species.toLowerCase())) return p.species;
    }
    final lines = raw
        .split('\n')
        .map((s) => s.trim())
        .where(
          (s) =>
              s.length >= 3 &&
              RegExp(r'[A-Za-zА-Яа-я]').hasMatch(s) &&
              !RegExp(
                r'\d|price|garden|plants|eur|usd|byn|цена|руб|[$€£₽]',
                caseSensitive: false,
              ).hasMatch(s),
        )
        .toList();
    return lines.isEmpty ? '' : lines.first;
  }

  /// Заполняет вид только ботаническим именем, присутствующим на этикетке.
  static String suggestSpecies(
    String raw,
    List<BotanicalProfile> profiles,
    String name,
  ) {
    final botanicalName = RegExp(r'^[A-Za-z]+ [A-Za-z-]+$');
    final knownNames =
        {
            for (final profile in profiles) ...[
              profile.species,
              ...profile.aliases,
            ],
          }.where((value) => botanicalName.hasMatch(value)).toList()
          ..sort((a, b) => b.length.compareTo(a.length));
    for (final candidate in knownNames) {
      final pattern = RegExp(
        r'\b' + RegExp.escape(candidate).replaceAll(' ', r'\s+') + r'\b',
        caseSensitive: false,
      );
      if (pattern.hasMatch(raw)) return candidate;
    }
    // Незнакомое ботаническое имя предлагается пользователю для подтверждения.
    return RegExp(r'^[A-Z][a-z]+ [a-z][a-z-]+$').hasMatch(name) ? name : '';
  }

  Future<void> _run(Future<String?> Function() operation) async {
    if (busy) return;
    busy = true;
    error = null;
    _emit();
    try {
      final raw = await operation();
      if (raw != null && !_disposed) {
        final profiles = await repository.load();
        if (_disposed) return;
        suggestion = suggestName(raw, profiles);
        speciesSuggestion = suggestSpecies(raw, profiles, suggestion);
        profile = profileFor(profiles, speciesSuggestion, suggestion);
        if (suggestion.isEmpty) {
          error =
              'Название не выделено. Введите его вручную или повторите снимок.';
        }
      }
    } on UnsupportedError {
      error = 'Распознавание доступно в Android-приложении.';
    } on FormatException {
      error = 'На изображении не найден текст. Сделайте более чёткий снимок.';
    } on PlatformException {
      error =
          'Не удалось открыть изображение или камеру. Проверьте разрешение и повторите.';
    } catch (_) {
      error = 'Не удалось распознать этикетку. Повторите попытку.';
    } finally {
      if (!_disposed) {
        busy = false;
        _emit();
      }
    }
  }

  Future<void> scanCamera() =>
      _run(() => service.pickAndRecognize(ImageSource.camera));
  Future<void> scanGallery() =>
      _run(() => service.pickAndRecognize(ImageSource.gallery));
  Future<void> scanSample(String asset) =>
      _run(() => service.recognizeSample(asset));
  Future<void> recover() => _run(service.recoverLostImage);
  void _emit() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    service.close();
    super.dispose();
  }
}
