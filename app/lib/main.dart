import 'package:flutter/material.dart';

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

void main() => runApp(const PpolingApp());

class PpolingApp extends StatelessWidget {
  const PpolingApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: '포폴링',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        routes: {
          '/': (_) => const CategoryScreen(),
          '/home': (_) => const HomeScreen(),
          '/dashboard': (_) => const DashboardScreen(),
          '/detail': (_) => const DetailScreen(),
          '/env': (_) => const EnvCheckScreen(),
          '/qa': (_) => const QaScreen(),
          '/settings': (_) => const SettingsScreen(),
          '/dialogs': (_) => const DialogsScreen(),
          '/ai': (_) => const AiScreen(),
        },
      );
}
