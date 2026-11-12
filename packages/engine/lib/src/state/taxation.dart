import '../accounting/ledger.dart';
import '../content/content_db.dart';
import '../core/ids.dart';
import '../core/money.dart';
import '../core/safe_int.dart';
import '../persistence/state_io.dart';
import '../reports/period_report.dart';
import 'entities.dart';
import 'world_state.dart';

/// What a chain's shops in the districts run by formula sold and made in one
/// country in one year, for that country's tax: their bookings carry no
/// store, so the company's reports can't tell where they were.
final class DistrictYear {
  DistrictYear({
    required this.company,
    required this.country,
    required this.year,
    this.sales = Money.zero,
    this.profit = Money.zero,
  });

  DistrictYear.read(StateReader reader)
    : company = CompanyId(reader.readInt()),
      country = CountryId(reader.readInt()),
      year = reader.readInt(),
      sales = Money(reader.readInt()),
      profit = Money(reader.readInt());

  final CompanyId company;
  final CountryId country;
  final int year;
  Money sales;
  Money profit;

  void write(StateWriter writer) {
    writer
      ..writeInt(company.index)
      ..writeInt(country.index)
      ..writeInt(year)
      ..writeInt(sales.cents)
      ..writeInt(profit.cents);
  }
}

/// A loss a company carries forward in one country after the first, whose
/// are [Company.lossCarried].
final class CountryLoss {
  CountryLoss({
    required this.company,
    required this.country,
    required this.amount,
  });

  CountryLoss.read(StateReader reader)
    : company = CompanyId(reader.readInt()),
      country = CountryId(reader.readInt()),
      amount = Money(reader.readInt());

  final CompanyId company;
  final CountryId country;
  Money amount;

  void write(StateWriter writer) {
    writer
      ..writeInt(company.index)
      ..writeInt(country.index)
      ..writeInt(amount.cents);
  }
}

/// A company's year in one country: what it made there before tax, the
/// losses it carries there, and the tax on what's left.
typedef CountryTax = ({
  CountryId country,
  Money sales,
  Money base,
  Money carried,
  Money tax,
});

/// The loss [company] carries in [country].
Money lossCarriedIn(WorldState world, Company company, CountryId country) {
  if (country.index == 0) return company.lossCarried;
  for (final loss in world.countryLosses) {
    if (loss.company == company.id && loss.country == country) {
      return loss.amount;
    }
  }
  return Money.zero;
}

/// Sets the loss [company] carries in [country] to [amount].
void setLossCarried(
  WorldState world,
  Company company,
  CountryId country,
  Money amount,
) {
  if (country.index == 0) {
    company.lossCarried = amount;
    return;
  }
  for (final loss in world.countryLosses) {
    if (loss.company == company.id && loss.country == country) {
      loss.amount = amount;
      return;
    }
  }
  if (amount == Money.zero) return;
  world.countryLosses.add(
    CountryLoss(company: company.id, country: country, amount: amount),
  );
}

/// Adds a month of a chain's shop in a district of [country] to [company]'s
/// year there.
void recordDistrictMonth(
  WorldState world,
  CompanyId company,
  CountryId country,
  int year, {
  required Money sales,
  required Money profit,
}) {
  for (final entry in world.districtYears) {
    if (entry.company == company &&
        entry.country == country &&
        entry.year == year) {
      entry
        ..sales += sales
        ..profit += profit;
      return;
    }
  }
  world.districtYears.add(
    DistrictYear(
      company: company,
      country: country,
      year: year,
      sales: sales,
      profit: profit,
    ),
  );
}

/// What [company] owes each country for [year], from its month reports of
/// the year so far: each country taxes what the company's stores and its
/// shops in districts made there, and a share of everything else (interest,
/// a director, fitting out, gains and losses on sales) by its share of the
/// sales, after the losses carried there. Only countries where the company
/// sold or made anything are listed. In a world of one country, that one
/// takes the whole year.
List<CountryTax> companyTaxes(
  WorldState world,
  ContentDb content,
  Company company,
  int year,
) {
  final countries = content.countries.length;
  final sales = List.filled(countries, Money.zero);
  final made = List.filled(countries, Money.zero);
  var base = Money.zero;
  var months = 0;
  for (final report in world.periodReports) {
    if (report.company != company.id ||
        report.period != ReportPeriod.month ||
        report.start.date.year != year) {
      continue;
    }
    months++;
    // The year's profit before the tax it paid on the year before.
    base += report.profit + report.flow(AccountKind.taxes);
    for (final store in report.stores) {
      final country = content.countryOf(world.stores[store.store.index].market);
      sales[country.index] += store.totalRevenue;
      made[country.index] += store.profit;
    }
  }
  for (final entry in world.districtYears) {
    if (entry.company != company.id || entry.year != year) continue;
    sales[entry.country.index] += entry.sales;
    made[entry.country.index] += entry.profit;
  }
  if (months == 0) return const [];
  var totalSales = Money.zero;
  var totalMade = Money.zero;
  for (var c = 0; c < countries; c++) {
    totalSales += sales[c];
    totalMade += made[c];
  }
  // What isn't any shop's goes by sales; with none, all of it to the
  // company's home.
  final rest = base - totalMade;
  final bases = List.of(made);
  if (totalSales > Money.zero) {
    var shared = Money.zero;
    var largest = 0;
    for (var c = 0; c < countries; c++) {
      final share = Money(
        mulDivRound(rest.cents, sales[c].cents, totalSales.cents),
      );
      bases[c] += share;
      shared += share;
      if (sales[c] > sales[largest]) largest = c;
    }
    bases[largest] += rest - shared;
  } else {
    bases[homeOf(world, content, company).index] += rest;
  }
  return [
    for (var c = 0; c < countries; c++)
      if (sales[c] != Money.zero || bases[c] != Money.zero)
        () {
          final country = CountryId(c);
          final carried = lossCarriedIn(world, company, country);
          final taxable = bases[c] - carried;
          final taxes = content.taxesOf(country);
          return (
            country: country,
            sales: sales[c],
            base: bases[c],
            carried: carried,
            tax: taxes == null || taxable <= Money.zero
                ? Money.zero
                : taxes.corporateTax(
                    taxable,
                    world.macroOf(country).priceIndex,
                  ),
          );
        }(),
  ];
}

/// Where [company] is from: the country of its first store, or else where
/// its owner lives.
CountryId homeOf(WorldState world, ContentDb content, Company company) {
  for (final store in world.stores) {
    if (store.company == company.id) return content.countryOf(store.market);
  }
  return world.residence(content, company.owner);
}
