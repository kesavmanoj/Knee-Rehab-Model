import 'package:flutter/material.dart';

import 'src/ui/knee_home_screen.dart';

class KneeMasterTestApp extends StatelessWidget {
  const KneeMasterTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KneeMaster BLE Test',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0B8F8C),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const KneeHomeScreen(),
    );
  }
}
