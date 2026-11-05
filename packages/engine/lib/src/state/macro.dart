import '../content/content_db.dart';
import '../core/fx.dart';
import '../core/ids.dart';
import '../persistence/state_io.dart';

/// The economy around the markets: the phase of the business cycle, the
/// price and wage levels, and the policy rate.
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
      policyRate: macro.policyRate(regime.inflation, regime),
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

  /// The central bank's annual rate, which new loans are priced from.
  Fx policyRate;

  /// Shelf prices over base reference prices, averaged over open stores, as
  /// measured last month; zero before the first measurement.
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
