import 'package:flutter/foundation.dart';
import '../models/care_guide.dart';
import '../services/plant_encyclopedia.dart';

/// Управляет загрузкой регламента, ошибкой и защитой от запоздалого ответа.
class CareGuideViewModel extends ChangeNotifier {
  CareGuideViewModel(this.encyclopedia);
  final PlantEncyclopedia encyclopedia;
  CareGuide? guide;
  bool loading = false;
  String? error;
  int _request = 0;
  bool _disposed = false;

  /// Последний запрос определяет результат; ответ старого поиска не меняет экран.
  Future<void> load(String query) async {
    final request = ++_request;
    loading = true;
    error = null;
    guide = null;
    notifyListeners();
    try {
      final result = await encyclopedia.fetch(query);
      if (_disposed || request != _request) return;
      guide = result;
    } on EncyclopediaException catch (e) {
      if (_disposed || request != _request) return;
      error = e.message;
    } catch (_) {
      if (_disposed || request != _request) return;
      error = 'Не удалось получить регламент. Повторите запрос.';
    }
    if (_disposed || request != _request) return;
    loading = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _request++;
    super.dispose();
  }
}
