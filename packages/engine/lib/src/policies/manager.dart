import '../accounting/ledger.dart';
import '../commands/command.dart';
import '../content/content_db.dart';
import '../core/fx.dart';
import '../core/money.dart';
import '../core/rng.dart';
import '../core/safe_int.dart';
import '../observation/observation.dart';
import '../state/entities.dart';
import '../state/store.dart';
import 'cushion.dart';
import 'director.dart';
import 'retail_policy.dart';

/// What the store managers of `view.actor` do today. Each plans its store as
/// a [RetailPolicy] would by its strategy, and gives only the commands within
/// its duties; pricing includes marketing, at the share of sales that pays
/// best (see [StorePlan.bestMarketingShare]), so a managed store builds its
/// goodwill and grows. Its demand
/// forecasts, traffic and target prices are off by up to its grade's share
/// of the scenario's errors, drawn from [judgment] once a week: mistakes
/// come from misjudging the market, never from blunders.
///
/// Orders share each company's uncommitted cash, store by store, in full
/// only beyond the company's [cashCushion]; within it, managers buy only
/// enough of their best sellers to keep selling, as long as there is
/// [cashForEssentials]. A manager trusted with investing enlarges or
/// converts the store as an owner would, once the company has made a
/// profit overall, from cash beyond the strategy's reserve and the year's
/// tax.
///
/// A company's director then acts with what its managers left (see
/// [direct]), their memos added to [directives], their site estimates
/// drawn from [foresight]; managers leave alone a store its director is
/// closing.
List<Command> manage(
  Observation view,
  ContentDb content,
  Rng Function(int entity) judgment, {
  Rng Function(int entity)? foresight,
  List<Directive>? directives,
}) {
  final commands = <Command>[];
  for (final company in view.companies) {
    if (company.status != CompanyStatus.active) continue;
    var budget = company.cash - company.committed;
    final cushion = cashCushion(view, content, company);
    var essentials = cashForEssentials(view, company);
    final profit =
        company.retainedEarnings + company.balance(AccountKind.dividends);
    final closing = closingStores(view, company);
    for (final store in company.stores) {
      final manager = store.manager;
      if (manager == null ||
          store.status == StoreStatus.closed ||
          closing.contains(store.id)) {
        continue;
      }
      final plan = StorePlan(
        content.strategies[manager.strategy.index],
        content,
        view,
        company,
        store,
        judgment: misjudgment(
          content,
          store,
          content.managers.grades[manager.grade.index],
          judgment,
          kept: content.directors?.kept(company.director?.grade) ?? Fx.one,
        ),
      );
      bool does(ManagerDuty duty) => manager.duties[duty.index];
      if (does(ManagerDuty.assortment)) commands.addAll(plan.assortment());
      if (does(ManagerDuty.pricing)) {
        commands
          ..addAll(plan.prices())
          ..addAll(plan.managedMarketing());
      }
      if (does(ManagerDuty.staffing)) commands.addAll(plan.staffing());
      if (does(ManagerDuty.ordering)) {
        final (orders, spent) = plan.orders(
          budget - cushion,
          essentials: essentials,
        );
        commands.addAll(orders);
        budget -= spent;
        essentials -= spent;
      }
      final reserve = operatingReserve(
        view,
        company,
        content.strategies[manager.strategy.index].reserveDays,
      );
      if (does(ManagerDuty.investing) &&
          reserve != null &&
          profit > Money.zero) {
        if (plan.conversion() case (
          :final format,
          :final cost,
        ) when cost <= budget - reserve - company.taxAccrued) {
          commands.add(
            ConvertStore(view.actor, store: store.id, format: format),
          );
          budget -= cost;
        } else if (plan.enlargementCost() case final cost?
            when cost <= budget - reserve - company.taxAccrued) {
          commands.add(ExpandStore(view.actor, store: store.id));
          budget -= cost;
        }
      }
    }
    if (company.director != null) {
      commands.addAll(
        direct(
          view,
          content,
          company,
          budget,
          closing,
          directives ?? [],
          judgment: foresight,
        ),
      );
    }
  }
  return commands;
}

/// How a manager of [grade] misjudges [store] this week: demand per product,
/// price per product and traffic, each drawn from [judgment] for an entity
/// of its own, and each kept to [kept] of what the grade allows by the
/// company's director (see [DirectorsDef.kept]).
Judgment misjudgment(
  ContentDb content,
  StoreView store,
  ManagerGradeDef grade,
  Rng Function(int entity) judgment, {
  Fx kept = Fx.one,
}) {
  final products = content.products.length;
  final unskilled = (Fx.one - grade.skill) * kept;
  final forecastError = content.managers.forecastError * unskilled;
  final priceError = content.managers.priceError * unskilled;
  Fx draw(int k, Fx error) =>
      judgmentFactor(judgment(store.id.index * (2 * products + 1) + k), error);
  return Judgment(
    demand: [for (var i = 0; i < products; i++) draw(i, forecastError)],
    price: [for (var i = 0; i < products; i++) draw(products + i, priceError)],
    traffic: draw(2 * products, forecastError),
  );
}

/// One plus a uniform draw from −[error] to +[error].
Fx judgmentFactor(Rng rng, Fx error) {
  final offset = rng.nextInt(2 * Fx.scale + 1) - Fx.scale;
  return Fx.one + Fx.raw(mulDivRound(error.raw, offset, Fx.scale));
}
