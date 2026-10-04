import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'views/garden_screen.dart';
import 'views/app_loader.dart';
import 'viewmodels/garden_view_model.dart';

/// Запускает приложение Flutter.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AppLoader());
}

/// Корневой виджет приложения с русской локалью и темой Material 3.
class PlantApp extends StatelessWidget {
  const PlantApp({super.key, this.viewModel, this.startupScreen});

  /// Необязательная зависимость для воспроизводимой проверки приложения.
  final GardenViewModel? viewModel;

  /// Экран открытия баз или ошибки до создания основного представления.
  final Widget? startupScreen;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Листва — домашние растения',
    debugShowCheckedModeBanner: false,
    // Физика ограничивает смещение, а эта настройка убирает растягивание
    // содержимого на границах всех списков и форм приложения.
    scrollBehavior: const MaterialScrollBehavior().copyWith(overscroll: false),
    locale: const Locale('ru'),
    supportedLocales: const [Locale('ru')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF285B43)),
      scaffoldBackgroundColor: const Color(0xFFF7F8F2),
      fontFamily: 'Roboto',
    ),
    home: startupScreen ?? GardenScreen(viewModel: viewModel),
  );
}
