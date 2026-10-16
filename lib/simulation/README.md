The pure Dart daily engine lives in simulation.dart. demand.dart contains consumer
intentions and choice weights; seeded_random.dart owns reproducible PRNG state.
No Flutter, wall-clock timers, persistence service, or backend is imported.

Use Simulation.neighborhood(seed: ...), advanceDay(), and the player's price and
restock-target setters. Inspect lastReport for accounting and market shares.
JSON snapshots preserve RNG, FIFO lots, prices, and prior sales so resumed games
have the same future. File/browser persistence is a later UI concern.

Run: dart tool/simulate.dart --days 10000 --seed 42
See ../../docs/economy.md for the model assumptions and supported controls.
