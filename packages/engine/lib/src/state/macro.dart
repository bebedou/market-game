import '../content/content_db.dart';
import '../core/fx.dart';
import '../core/ids.dart';
import '../persistence/state_io.dart';
import 'public_record.dart';

/// A country's economy around its markets: the phase of the business cycle,
/// the price and wage levels, unemployment, and the policy rate.
final class MacroState {
  MacroState({
    required this.regime,
    required this.monthsInRegime,
    required this.priceIndex,
    required this.wageIndex,
    required this.inflation,
    required this.policyRate,
    required this.retailLevel,
    this.unemployment = Fx.zero,
  });

  /// A copy of [other], as a country added to a saved game starts.
  MacroState.copyOf(MacroState other)
    : regime = other.regime,
      monthsInRegime = other.monthsInRegime,
      priceIndex = other.priceIndex,
      wageIndex = other.wageIndex,
      inflation = other.inflation,
      policyRate = other.policyRate,
      retailLevel = other.retailLevel,
      unemployment = other.unemployment;

  /// The economy at the scenario's start: price and wage indices at 1, and
  /// the start regime's inflation.
  factory MacroState.initial(MacroDef macro) {
    final regime = macro.regimes[macro.startRegime.index];
    return MacroState(
      regime: regime.id,
      monthsInRegime: 0,
      priceIndex: Fx.one,
      wageIndex: Fx.one,
      inflation: regime.inflation,
      policyRate: macro.policyRate(regime.inflation, regime.outputGap),
      retailLevel: Fx.zero,
      unemployment: macro.labour?.naturalUnemployment ?? Fx.zero,
    );
  }

  MacroState.read(StateReader reader)
    : regime = RegimeId(reader.readInt()),
      monthsInRegime = reader.readInt(),
      priceIndex = Fx.raw(reader.readInt()),
      wageIndex = Fx.raw(reader.readInt()),
      inflation = Fx.raw(reader.readInt()),
      policyRate = Fx.raw(reader.readInt()),
      retailLevel = Fx.raw(reader.readInt()),
      unemployment = reader.version >= 12 ? Fx.raw(reader.readInt()) : Fx.zero;

  RegimeId regime;
  int monthsInRegime;

  /// Prices relative to the scenario's start. Supplier prices, households'
  /// reference prices, rents and opening costs scale with it.
  Fx priceIndex;

  /// Wages relative to the scenario's start.
  Fx wageIndex;

  /// The latest annual inflation rate.
  Fx inflation;

  /// The central bank's annual rate, which new loans are priced from: the
  /// same in every country on its currency.
  Fx policyRate;

  /// Shelf prices over base reference prices, averaged over the country's
  /// open stores, as measured last month; zero before the first measurement.
  Fx retailLevel;

  /// The share of the labour force out of work; zero if not modelled.
  Fx unemployment;

  void write(StateWriter writer) {
    writer
      ..writeInt(regime.index)
      ..writeInt(monthsInRegime)
      ..writeInt(priceIndex.raw)
      ..writeInt(wageIndex.raw)
      ..writeInt(inflation.raw)
      ..writeInt(policyRate.raw)
      ..writeInt(retailLevel.raw)
      ..writeInt(unemployment.raw);
  }
}

/// The economy of a country after the first, whose own is
/// `WorldState.macro`, and its history month by month. Kept beside the
/// world, as a world of one country has none.
final class Economy {
  Economy({required this.macro, required this.history});

  Economy.read(StateReader reader)
    : macro = MacroState.read(reader),
      history = [
        for (var i = 0, n = reader.readInt(); i < n; i++)
          readEconomicMonth(reader),
      ];

  final MacroState macro;

  /// Oldest first, as `WorldState.economicHistory` is the first country's.
  final List<EconomicMonth> history;

  void write(StateWriter writer) {
    macro.write(writer);
    writer.writeInt(history.length);
    for (final month in history) {
      writeEconomicMonth(writer, month);
    }
  }
}

/// The cycle that the countries on one currency share, which each follows
/// more or less closely (see `CountryDef.follows`). A world of one country
/// has none: its own cycle is the one.
final class SharedCycle {
  SharedCycle({required this.regime, required this.monthsInRegime});

  SharedCycle.read(StateReader reader)
    : regime = RegimeId(reader.readInt()),
      monthsInRegime = reader.readInt();

  RegimeId regime;
  int monthsInRegime;

  void write(StateWriter writer) {
    writer
      ..writeInt(regime.index)
      ..writeInt(monthsInRegime);
  }
}
