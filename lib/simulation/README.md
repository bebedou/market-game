Pure Dart systems belong here: seeded randomness, daily demand, purchasing,
restocking, competitor pricing, and accounting. Do not import Flutter or UI code.

The UI should invoke the engine and display its output. Real-time timers and
local persistence belong outside the engine. The engine must advance in discrete
days and serialize its random state to make save/resume deterministic.

No simulation is implemented in this environment setup.
