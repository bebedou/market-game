import '../commands/apply_command.dart' show maxNameLength;
import '../commands/refusal.dart';
import '../content/content_db.dart';
import '../core/ids.dart';
import '../core/money.dart';
import '../core/safe_int.dart';
import '../persistence/state_io.dart';

/// Where and how the player chose to start: the site and format of their
/// first store, and the name it and their company go by; or, for a
/// [GameStart.holding], only their holding's name, with no business yet.
/// Without one, the game starts as the scenario sets out.
final class GameStart {
  const GameStart({
    required SiteId this.site,
    required FormatId this.format,
    required this.name,
  });

  /// The player starts with a holding named [name] and no business: the
  /// scenario's company for them sleeps, its cash theirs, and they start
  /// their first business where they like.
  const GameStart.holding(this.name) : site = null, format = null;

  GameStart.read(StateReader reader)
    : site = switch (reader.readInt()) {
        < 0 => null,
        final index => SiteId(index),
      },
      format = switch (reader.readInt()) {
        < 0 => null,
        final index => FormatId(index),
      },
      name = reader.readString();

  /// The first store's site and format; null for a holding start.
  final SiteId? site;
  final FormatId? format;
  final String name;

  /// Whether the player starts with only a holding, named [name].
  bool get holding => site == null;

  void write(StateWriter writer) {
    writer
      ..writeInt(site?.index ?? -1)
      ..writeInt(format?.index ?? -1)
      ..writeString(name);
  }

  @override
  String toString() => holding
      ? 'GameStart.holding($name)'
      : 'GameStart(site: ${site!.index}, format: ${format!.index}, '
            'name: $name)';
}

/// What a [GameStart] comes to. The player starts as well off as with the
/// scenario's own first store: what fitting out the chosen store costs
/// beyond it comes out of the company's cash, and the player's own if the
/// company would keep less than [minStartingCash]; a cheaper store leaves
/// the company the difference. With a holding start, the company's cash
/// and what its store would have cost are the player's own, and nothing
/// is fitted out.
typedef StartTerms = ({
  /// Fitting out the chosen store.
  Money fitOut,
  Money companyCash,
  Money personalCash,

  /// Personal cash put into the company to start.
  Money capital,
});

/// The least cash the player's company starts with.
const Money minStartingCash = Money(1000000);

/// The scenario's first store for the player, and its company: what a
/// [GameStart] replaces. Null if the scenario gives the player none.
({int store, int company})? playerSetup(ContentDb content) {
  final player = content.player;
  for (final (i, store) in content.stores.indexed) {
    final company = content.companies[store.company.index];
    if (company.owner == player) {
      return (store: i, company: store.company.index);
    }
  }
  return null;
}

/// The sites the player may start on: those no other store of the
/// scenario's holds.
List<SiteId> startingSites(ContentDb content) {
  final setup = playerSetup(content);
  final held = {
    for (final (i, store) in content.stores.indexed)
      if (i != setup?.store) store.site.index,
  };
  return [
    for (final site in content.sites)
      if (!held.contains(site.id.index)) site.id,
  ];
}

/// The terms of [start], or why the player can't start that way.
(StartTerms?, Refusal?) startTerms(ContentDb content, GameStart start) {
  final setup = playerSetup(content);
  if (setup == null) return (null, const Refusal('noStartingStore'));
  final name = start.name;
  if (name.trim() != name || name.isEmpty || name.length > maxNameLength) {
    return (null, const Refusal('nameRule', count: maxNameLength));
  }
  final usual = content.stores[setup.store];
  final usualFitOut = content.sites[usual.site.index].openingCost.times(
    content.formats[usual.format.index].fitOut,
  );
  final player = content.persons[content.player.index];
  final (chosenSite, chosenFormat) = (start.site, start.format);
  if (chosenSite == null || chosenFormat == null) {
    return (
      (
        fitOut: Money.zero,
        companyCash: Money.zero,
        personalCash:
            player.cash + content.companies[setup.company].cash + usualFitOut,
        capital: Money.zero,
      ),
      null,
    );
  }
  if (chosenSite.index < 0 || chosenSite.index >= content.sites.length) {
    return (null, const Refusal('unknownSite'));
  }
  if (!startingSites(content).contains(chosenSite)) {
    return (null, const Refusal('siteTaken'));
  }
  if (chosenFormat.index < 0 || chosenFormat.index >= content.formats.length) {
    return (null, const Refusal('unknownFormat'));
  }
  final site = content.sites[chosenSite.index];
  final format = content.formats[chosenFormat.index];
  if (format.minArea > site.area) {
    return (null, Refusal('siteTooSmall', format: format.id));
  }
  final fitOut = site.openingCost.times(format.fitOut);
  var companyCash =
      content.companies[setup.company].cash + usualFitOut - fitOut;
  var personalCash = player.cash;
  var capital = Money.zero;
  if (companyCash < minStartingCash) {
    capital = minStartingCash - companyCash;
    if (capital > personalCash) {
      return (null, Refusal('fitOutTooDear', amount: fitOut));
    }
    personalCash -= capital;
    companyCash = minStartingCash;
  }
  return (
    (
      fitOut: fitOut,
      companyCash: companyCash,
      personalCash: personalCash,
      capital: capital,
    ),
    null,
  );
}

/// Shelf prices and staff for a first store of [format] in [market]: those
/// of the scenario's first store of the format, the player's own first, at
/// [market]'s price level; or, if there is none, the reference price of
/// every product the format sells, as far as the shelves go, and one member
/// of staff in each slot but the night.
({List<Money?> prices, List<int> staff}) startingShop(
  ContentDb content,
  FormatId format,
  MarketId market, {
  required int shelfSlots,
}) {
  final setup = playerSetup(content);
  final candidates = [
    if (setup != null) content.stores[setup.store],
    ...content.stores,
  ];
  final level = content.markets[market.index].priceLevel;
  for (final store in candidates) {
    if (store.format != format) continue;
    final from = content.markets[content.sites[store.site.index].market.index];
    final ratio = level.div(from.priceLevel);
    final country = content.countryOf(market);
    return (
      // As dear here as there, and at this country's normal prices.
      prices: [
        for (final (p, price) in store.prices.indexed)
          if (price == null)
            null
          else if (country == from.country)
            price.times(ratio)
          else
            Money(
              mulDivRound(
                price.times(ratio).cents,
                content.referenceIn(content.products[p], country).cents,
                content.referenceIn(content.products[p], from.country).cents,
              ),
            ),
      ],
      staff: List.of(store.staff),
    );
  }
  final sells = content.formats[format.index].sells;
  var listed = 0;
  return (
    prices: [
      for (final product in content.products)
        if (sells[product.category.index] && listed++ < shelfSlots)
          content.referenceIn(product, content.countryOf(market)).times(level)
        else
          null,
    ],
    staff: [for (final slot in DaySlot.values) slot == DaySlot.night ? 0 : 1],
  );
}
