import 'package:engine/engine.dart';
import 'package:flutter/material.dart';

import '../controller.dart';
import '../format.dart';
import '../l10n.dart';
import '../theme.dart';
import '../widgets.dart';
import 'factory.dart' show BuildFactoryPage;
import 'software.dart' show StartSoftwarePage;
import 'world.dart' show NewBusiness, freeSites;

/// Opens the page to start a business, or with [subsidiary] a company of its
/// own for the holding, within the current tab.
void openStartBusiness(BuildContext context, {bool subsidiary = false}) {
  final title = subsidiary
      ? tr('common.startSubsidiary')
      : tr('common.startBusiness');
  context.openPage(title, (_) => [StartBusinessPage(subsidiary: subsidiary)]);
}

/// A kind of business: its name, what sets it apart, its colour, the least
/// it costs to set up if known, and what opens the page that starts one.
typedef _Kind = ({
  String name,
  String pitch,
  Color mark,
  Money? from,
  void Function(BuildContext context) open,
});

/// A sector and its kinds of business.
typedef _Sector = ({String key, String name, Color mark, List<_Kind> kinds});

/// The sectors a business can be started in: each trade's kinds of shop, in
/// the order the formats come, then factories and software where the
/// scenario has them. A subsidiary is a shop or a factory.
List<_Sector> _sectors(
  SimulationController game,
  Ledger ledger, {
  required bool subsidiary,
}) {
  final content = game.content;
  final sites = freeSites(game);
  _Kind shop(FormatDef format) {
    // Its fitting out on the cheapest vacant site big enough for it.
    Money? from;
    for (final site in sites) {
      if (site.area < format.minArea) continue;
      final cost = site.openingCost
          .times(format.fitOut)
          .times(game.economyAt(site.market).priceIndex);
      if (from == null || cost < from) from = cost;
    }
    return (
      name: format.name,
      // What limits it first, where a long line is cut.
      pitch: [
        if (format.minArea > 0)
          tr('business.leastArea', {'area': format.minArea}),
        if (from == null) tr('business.noSiteLine'),
        ?trMaybe('business.pitches.${format.key}'),
      ].join(' · '),
      mark: ledger.trade(format),
      from: from,
      open: (context) => context.openPage(
        format.name,
        (_) => [NewBusiness(format: format.id, subsidiary: subsidiary)],
      ),
    );
  }

  final trades = <String, List<FormatDef>>{};
  for (final format in content.formats) {
    trades
        .putIfAbsent(formatTrades[format.key] ?? format.key, () => [])
        .add(format);
  }
  return [
    for (final MapEntry(:key, value: formats) in trades.entries)
      (
        key: key,
        name:
            trMaybe('business.sectors.$key') ??
            (formats.length == 1 ? formats.single.name : key),
        mark: ledger.trade(formats.first),
        kinds: [for (final format in formats) shop(format)],
      ),
    if (content.factories case final factories?)
      (
        key: 'factories',
        name: tr('business.sectors.factories'),
        mark: ledger.works,
        kinds: [
          for (final kind in factories.kinds)
            (
              name: kind.name,
              pitch: [
                for (final product in content.products)
                  if (product.category == kind.category) product.name,
              ].join(', '),
              mark: ledger.works,
              // The smallest size, at home.
              from: factories
                  .sized(kind.id, 0)
                  .buildCost
                  .times(game.view.economy(game.homeCountry).priceIndex),
              open: (context) => context.openPage(
                kind.name,
                (_) => [
                  BuildFactoryPage(kind: kind.id, subsidiary: subsidiary),
                ],
              ),
            ),
        ],
      ),
    if (content.software != null && !subsidiary)
      (
        key: 'software',
        name: tr('business.sectors.software'),
        mark: ledger.software,
        kinds: [
          (
            name: tr('business.software'),
            pitch: tr('software.startPitch'),
            mark: ledger.software,
            from: null,
            open: (context) => context.openPage(
              tr('software.start'),
              (_) => [const StartSoftwarePage()],
            ),
          ),
        ],
      ),
  ];
}

/// Starting a business, the owner's layout A: a line for each sector, with
/// its colour and its kinds, each opening the sector's kinds of business.
class StartBusinessPage extends StatelessWidget {
  const StartBusinessPage({super.key, this.subsidiary = false});

  /// Whether it is a company of its own for the holding.
  final bool subsidiary;

  @override
  Widget build(BuildContext context) {
    final sectors = _sectors(
      context.game,
      Ledger.of(context),
      subsidiary: subsidiary,
    );
    // A page shows no title of its own: its section says what it is.
    return Section(
      title: subsidiary
          ? tr('common.startSubsidiary')
          : tr('common.startBusiness'),
      children: [
        Hint(
          subsidiary
              ? tr('business.subsidiaryHint')
              : tr('business.pickSector'),
        ),
        for (final sector in sectors)
          IndexRow(
            mark: sector.mark,
            title: sector.name,
            subtitle: [for (final kind in sector.kinds) kind.name].join(' · '),
            value: '${sector.kinds.length}',
            onTap: () => context.openPage(
              sector.name,
              (_) => [_SectorPage(sector: sector.key, subsidiary: subsidiary)],
            ),
          ),
      ],
    );
  }
}

/// A sector's kinds of business, a line each with what sets it apart and the
/// least it costs to set up, each opening the page that starts one.
class _SectorPage extends StatelessWidget {
  const _SectorPage({required this.sector, required this.subsidiary});

  final String sector;
  final bool subsidiary;

  @override
  Widget build(BuildContext context) {
    final chosen = _sectors(
      context.game,
      Ledger.of(context),
      subsidiary: subsidiary,
    ).firstWhere((each) => each.key == sector);
    return Section(
      title: chosen.name,
      mark: chosen.mark,
      children: [
        for (final kind in chosen.kinds)
          IndexRow(
            mark: kind.mark,
            title: kind.name,
            subtitle: kind.pitch,
            value: kind.from == null
                ? null
                : tr('business.from', {'amount': compactMoney(kind.from!)}),
            onTap: () => kind.open(context),
          ),
      ],
    );
  }
}
