import 'dart:async';
import 'package:flutter/material.dart';
import '../main.dart';
import '../services/garden_resources.dart';
import '../services/storage_bootstrap_native.dart'
    if (dart.library.js_interop) '../services/storage_bootstrap_web.dart';

/// Отображает состояние открытия баз, а при ошибке предлагает повторить загрузку.
class AppLoader extends StatefulWidget {
  const AppLoader({super.key});
  @override
  State<AppLoader> createState() => _AppLoaderState();
}

class _AppLoaderState extends State<AppLoader> {
  late Future<GardenResources> opening;
  GardenResources? resources;
  bool _closed = false;
  @override
  void initState() {
    super.initState();
    opening = _open();
  }

  Future<GardenResources> _open() async {
    final value = await openGarden();
    if (_closed) {
      await value.close();
    } else {
      resources = value;
    }
    return value;
  }

  @override
  void dispose() {
    _closed = true;
    if (resources != null) {
      unawaited(resources!.close().catchError((Object _) {}));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<GardenResources>(
    future: opening,
    builder: (context, state) {
      if (state.hasData) return PlantApp(viewModel: state.data!.garden);
      return PlantApp(
        startupScreen: Scaffold(
          body: Center(
            child: state.hasError
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Не удалось открыть сохранённые данные. Повторите попытку.',
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: () => setState(() {
                            opening = _open();
                          }),
                          child: const Text('Повторить'),
                        ),
                      ],
                    ),
                  )
                : const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Загрузка сада…'),
                    ],
                  ),
          ),
        ),
      );
    },
  );
}
