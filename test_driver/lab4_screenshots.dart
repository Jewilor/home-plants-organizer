import 'dart:convert';
import 'dart:io';
import 'package:integration_test/integration_test_driver_extended.dart';

/// Сохраняет настоящие снимки Android и результат проверки четвёртой лабораторной.
Future<void> main() => integrationDriver(
  onScreenshot: (name, bytes, [args]) async {
    final directory = Directory('screenshots/lab4');
    await directory.create(recursive: true);
    await File('${directory.path}/$name.png').writeAsBytes(bytes);
    return true;
  },
  responseDataCallback: (data) async {
    if (data == null) return;
    final directory = Directory('screenshots/lab4');
    await directory.create(recursive: true);
    for (final screenshot in data['screenshots'] as List? ?? []) {
      await File(
        '${directory.path}/${screenshot['screenshotName']}.png',
      ).writeAsBytes(List<int>.from(screenshot['bytes'] as List));
    }
    final qa = Directory('reports/qa/lab4');
    await qa.create(recursive: true);
    await File(
      '${qa.path}/${data['verification']?['restored'] == true ? 'restore' : 'integration'}.json',
    ).writeAsString(
      const JsonEncoder.withIndent('  ').convert(data['verification']),
    );
  },
);
