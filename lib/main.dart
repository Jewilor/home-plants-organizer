import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'views/garden_screen.dart';

/// Запускает приложение Flutter.
void main() => runApp(const PlantApp());

/// Корневой виджет приложения с русской локалью и темой Material 3.
class PlantApp extends StatelessWidget {
  const PlantApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Листва — домашние растения',
    debugShowCheckedModeBanner: false,
    locale: const Locale('ru'),
    supportedLocales: const [Locale('ru')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF285B43)),
      scaffoldBackgroundColor: const Color(0xFFF7F8F2),
      fontFamily: 'Roboto',
    ),
    home: const GardenScreen(),
  );
}
