import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

/// Источник изображения для распознавания названия: снимок, галерея или образец.
abstract interface class LabelRecognitionService {
  Future<String?> pickAndRecognize(ImageSource source);
  Future<String> recognizeSample(String asset);
  Future<String?> recoverLostImage();
  Future<void> close();
}

/// Выполняет настоящее распознавание латинского текста на устройстве Android.
/// Образцы этикеток проходят тот же распознаватель, что и снимок камеры.
class MlKitLabelRecognitionService implements LabelRecognitionService {
  final ImagePicker _picker = ImagePicker();
  final TextRecognizer _recognizer = TextRecognizer(
    script: TextRecognitionScript.latin,
  );
  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  void _checkPlatform() {
    if (!supported) {
      throw UnsupportedError('Распознавание доступно в Android-приложении.');
    }
  }

  Future<String> _recognize(String path) async {
    _checkPlatform();
    final result = await _recognizer.processImage(
      InputImage.fromFilePath(path),
    );
    if (result.text.trim().isEmpty) {
      throw FormatException('На изображении не найден текст.');
    }
    return result.text;
  }

  @override
  Future<String?> pickAndRecognize(ImageSource source) async {
    _checkPlatform();
    final image = await _picker.pickImage(
      source: source,
      maxWidth: 2000,
      imageQuality: 95,
    );
    return image == null ? null : _recognize(image.path);
  }

  @override
  Future<String> recognizeSample(String asset) async {
    _checkPlatform();
    final bytes = await rootBundle.load(asset);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${asset.split('/').last}');
    await file.writeAsBytes(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    );
    return _recognize(file.path);
  }

  @override
  Future<String?> recoverLostImage() async {
    if (!supported) return null;
    final lost = await _picker.retrieveLostData();
    if (lost.exception != null) throw lost.exception!;
    return lost.files == null || lost.files!.isEmpty
        ? null
        : _recognize(lost.files!.first.path);
  }

  @override
  Future<void> close() async {
    if (supported) await _recognizer.close();
  }
}
