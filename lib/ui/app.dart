import 'package:flutter/material.dart';

class MarketGameApp extends StatelessWidget {
  const MarketGameApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Market Game',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF146C59)),
        useMaterial3: true,
      ),
      home: const _SetupScreen(),
    );
  }
}

class _SetupScreen extends StatelessWidget {
  const _SetupScreen();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Market Game')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.storefront_outlined,
                    size: 56,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 24),
                  Text('Your neighborhood starts here.',
                      style: textTheme.headlineMedium),
                  const SizedBox(height: 16),
                  Text('Development environment ready',
                      style: textTheme.titleMedium),
                  const SizedBox(height: 8),
                  const Text(
                    'The pure Dart economy now models households, inventory, '
                    'suppliers, and competing convenience stores. The next '
                    'milestone is the playable dashboard.',
                  ),
                  const SizedBox(height: 24),
                  const Text('Dashboard controls and local saves are coming next.'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
