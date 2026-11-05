import '../core/calendar.dart';
import '../core/fx.dart';
import '../core/ids.dart';
import '../core/money.dart';
import '../persistence/state_io.dart';

/// A company's accounts for a calendar year, public as French companies'
/// are: what it sold, the profit it made, and its stores at the year's end.
typedef Filing = ({
  CompanyId company,
  int year,
  Money revenue,
  Money profit,
  int stores,
});

/// The economy at the start of a month.
typedef EconomicMonth = ({
  Day day,
  RegimeId regime,
  Fx priceIndex,
  Fx wageIndex,
  Fx inflation,
  Fx policyRate,
  Fx unemployment,
});

/// Years of filings kept.
const int filingYearsKept = 10;

/// Months of economic history kept.
const int economicMonthsKept = 240;

Filing readFiling(StateReader reader) => (
  company: CompanyId(reader.readInt()),
  year: reader.readInt(),
  revenue: Money(reader.readInt()),
  profit: Money(reader.readInt()),
  stores: reader.readInt(),
);

void writeFiling(StateWriter writer, Filing filing) => writer
  ..writeInt(filing.company.index)
  ..writeInt(filing.year)
  ..writeInt(filing.revenue.cents)
  ..writeInt(filing.profit.cents)
  ..writeInt(filing.stores);

EconomicMonth readEconomicMonth(StateReader reader) => (
  day: Day(reader.readInt()),
  regime: RegimeId(reader.readInt()),
  priceIndex: Fx.raw(reader.readInt()),
  wageIndex: Fx.raw(reader.readInt()),
  inflation: Fx.raw(reader.readInt()),
  policyRate: Fx.raw(reader.readInt()),
  unemployment: Fx.raw(reader.readInt()),
);

void writeEconomicMonth(StateWriter writer, EconomicMonth month) => writer
  ..writeInt(month.day.number)
  ..writeInt(month.regime.index)
  ..writeInt(month.priceIndex.raw)
  ..writeInt(month.wageIndex.raw)
  ..writeInt(month.inflation.raw)
  ..writeInt(month.policyRate.raw)
  ..writeInt(month.unemployment.raw);
