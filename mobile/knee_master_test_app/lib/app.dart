import 'package:flutter/material.dart';

import 'src/ui/knee_home_screen.dart';

class KneeMasterTestApp extends StatelessWidget {
  const KneeMasterTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF0B8F8C),
      brightness: Brightness.light,
    );

    return MaterialApp(
      title: 'Knee Rehab Monitor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: colorScheme,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF4F7FB),
        appBarTheme: AppBarTheme(
          backgroundColor: colorScheme.surface,
          foregroundColor: colorScheme.onSurface,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          color: colorScheme.surface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: colorScheme.outlineVariant),
          ),
        ),
      ),
      home: const KneeHomeScreen(),
    );
  }
}
