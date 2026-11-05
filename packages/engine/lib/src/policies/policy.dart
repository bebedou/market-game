import '../commands/command.dart';
import '../content/content_db.dart';
import '../core/ids.dart';
import '../observation/observation.dart';
import 'entrepreneur_policy.dart';
import 'retail_policy.dart';

/// Turns what an actor sees into the commands it gives. AI owners, strategy
/// bots and, later, the player's managers are all policies, bound by the same
/// rules and the same information as the player.
abstract interface class Policy {
  /// Commands for `view.actor`, applied at the start of `view.today`.
  List<Command> decide(Observation view, ContentDb content);
}

/// An [ownerPolicy] for every person the scenario gives a strategy.
Map<PersonId, Policy> standardPolicies(ContentDb content) => {
  for (final (i, person) in content.persons.indexed)
    if (person.strategy case final strategy?)
      PersonId(i): person.local
          ? RetailPolicy(content.strategies[strategy.index])
          : ownerPolicy(content.strategies[strategy.index]),
};

/// A [RetailPolicy] running the actor's stores and, if the strategy expands,
/// an [EntrepreneurPolicy] opening new ones.
Policy ownerPolicy(StrategyDef strategy) => strategy.expansionPaybackMonths == 0
    ? RetailPolicy(strategy)
    : CombinedPolicy([RetailPolicy(strategy), EntrepreneurPolicy(strategy)]);

/// Several policies acting for one actor, their commands in order.
final class CombinedPolicy implements Policy {
  const CombinedPolicy(this.policies);

  final List<Policy> policies;

  @override
  List<Command> decide(Observation view, ContentDb content) => [
    for (final policy in policies) ...policy.decide(view, content),
  ];
}
