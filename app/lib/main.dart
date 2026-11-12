import 'package:flutter/material.dart';
import 'package:ppoling_core/contracts.dart';
import 'package:ppoling_core/fakes.dart';
import 'package:ppoling_runner/runner.dart' as runner;

import 'registry.dart';
import 'screens/ai_screen.dart';
import 'screens/category_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/detail_screen.dart';
import 'screens/dialogs_screen.dart';
import 'screens/env_check_screen.dart';
import 'screens/home_screen.dart';
import 'screens/qa_screen.dart';
import 'screens/settings_screen.dart';
import 'ui/theme.dart';

void main() => runApp(PpolingApp(registry: buildRegistry()));

/// 가짜 구현과 목업 화면을 먼저 깔고, 기능의 `register()` 로 덮어쓴다.
/// 진짜 기능이 생기면 아래 목록에 `<기능>.register(app);` 한 줄을 더한다.
Registry buildRegistry() {
  final app = Registry();
  _registerFakes(app);
  _registerMockups(app);
  runner.register(app);
  return app;
}

void _registerFakes(AppRegistry app) {
  final projects = FakeProjectRepository.withSamples();
  app.provide<ProjectRepository>(projects);
  app.provide<ConfigValidator>(FakeConfigValidator());
  app.provide<QaRunner>(FakeQaRunner(projects));
  app.provide<PortProbe>(FakePortProbe());
  app.provide<RuntimeQuery>(FakeRuntimeQuery());
}

void _registerMockups(AppRegistry app) {
  app.route('/', (_) => const CategoryScreen());
  app.route('/home', (_) => const HomeScreen());
  app.route('/dashboard', (_) => const DashboardScreen());
  app.route('/detail', (_) => const DetailScreen());
  app.route('/env', (_) => const EnvCheckScreen());
  app.route('/qa', (_) => const QaScreen());
  app.route('/settings', (_) => const SettingsScreen());
  app.route('/dialogs', (_) => const DialogsScreen());
  app.route('/ai', (_) => const AiScreen());
}

class PpolingApp extends StatelessWidget {
  const PpolingApp({super.key, required this.registry});

  final Registry registry;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: '포폴링',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        routes: registry.routes,
      );
}
