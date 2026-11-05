import 'package:flutter/material.dart';

import '../l10n.dart';
import '../widgets.dart';

/// The guide's topics: an icon, and its key in the words.
const _topics = <(IconData, String)>[
  (Icons.flag_outlined, 'goal'),
  (Icons.schedule, 'time'),
  (Icons.dashboard_outlined, 'holding'),
  (Icons.storefront_outlined, 'store'),
  (Icons.local_shipping_outlined, 'orders'),
  (Icons.receipt_long_outlined, 'reports'),
  (Icons.public, 'market'),
  (Icons.handshake_outlined, 'deals'),
  (Icons.lightbulb_outline, 'tips'),
];

/// A short guide to the game: its aim, the screens and the main decisions.
class HowToPlayScreen extends StatelessWidget {
  const HowToPlayScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr('common.howToPlay'))),
    body: ListView(
      padding: const EdgeInsets.symmetric(vertical: 6),
      children: [
        for (final (icon, topic) in _topics)
          Section(
            title: tr('guide.$topic.title'),
            icon: icon,
            children: [
              for (final paragraph in trList('guide.$topic.paragraphs'))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(paragraph),
                ),
            ],
          ),
      ],
    ),
  );
}
