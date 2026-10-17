import '../domain/economy.dart';
import 'seeded_random.dart';

/// Aggregate purchase intentions; realized sales also depend on price and budget.
class ConsumerDemand {
  static const weekdayPercent = [100, 100, 100, 105, 115, 130, 110];
  static const outsideWeight = 350;

  static int desiredUnits(
    ConsumerSegment segment,
    Product product,
    int day,
    SeededRandom random,
  ) {
    final noisePercent = 90 + random.nextInt(21);
    return random.roundRatio(
      segment.households *
          product.dailyDemandPerThousand *
          weekdayPercent[(day - 1) % 7] *
          noisePercent,
      1000 * 100 * 100,
    );
  }

  static int storeWeight(
    ConsumerSegment segment,
    Product product,
    int price,
    int appeal,
  ) {
    if (price <= 0 || appeal <= 0) {
      throw ArgumentError('Invalid store offer.');
    }
    final reservationPrice =
        product.referencePrice * (100 + 120 ~/ segment.priceSensitivity) ~/ 100;
    if (price > reservationPrice) {
      return 0;
    }
    var weight = 1000;
    for (var i = 0; i < segment.priceSensitivity; i++) {
      weight = (weight * product.referencePrice ~/ price)
          .clamp(1, 1000000)
          .toInt();
    }
    return weight * appeal ~/ 100;
  }
}
