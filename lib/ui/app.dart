import 'package:flutter/material.dart';

import '../application/game_controller.dart';
import 'dashboard.dart';

class MarketGameApp extends StatelessWidget {
  const MarketGameApp({super.key, this.controller});

  final GameController? controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Market Game — Economy monitor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF226C52),
          surface: Colors.white,
        ),
        scaffoldBackgroundColor: const Color(0xFFF3F5F2),
        useMaterial3: true,
        dividerColor: const Color(0xFFE5E9E3),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF3F5F2),
          foregroundColor: Color(0xFF18352C),
          surfaceTintColor: Colors.transparent,
        ),
      ),
      home: DashboardScreen(controller: controller),
    );
  }
}
