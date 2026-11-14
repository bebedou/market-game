# Market Game wiki

A map of how Market Game is built, for anyone (person or session) who needs
context fast. It summarises and links; the detailed design lives in
[Engine Architecture.md](<../Engine Architecture.md>) and the game's intent in
[Game Design.md](<../Game Design.md>).

Start with the overview, then go to the page for the part you are touching.

| Page | What it covers |
|---|---|
| [Overview and repo map](overview.md) | What the game is, the three packages, the rules that hold everywhere, how to run things |
| [Engine core](engine-core.md) | Integer maths, determinism, the `Simulation` facade, the daily tick, commands and refusals, policies, observations |
| [State and saves](state-and-saves.md) | `WorldState`, the canonical encoding, the save layout, version gating, growing worlds, replays, the state hash |
| [Content and scenarios](content-and-scenarios.md) | `ContentDb`, the loader, IDs as list positions, the scenario's words, neighbourhoods and cities asleep |
| [National economy](national-economy.md) | Countries by formula, chains and company blocks, directors' compounding growth, buying terms, brands, factories |
| [The app](app.md) | Flutter bootstrap, `SimulationController`, the five tabs and their files, the ledger theme, `tr()`, ink maps, saves on disk |
| [Testing](testing.md) | VM and Node engine tests, goldens, fixtures, app widget tests, l10n checks, the device tour |
| [Tools and scripts](tools-and-scripts.md) | The headless runner and balance tools, the Eurostat build scripts, how content data is regenerated |
| [Where to find X](where-to-find.md) | A lookup from "I want to change…" to the file and symbol |
| [Technical debt](tech-debt.md) | Known problems in the code, each with its file and why it matters |

## How to read the links

Links go to files, not lines, because line numbers move with every commit.
Each page names the symbol to search for in the linked file.

## Keeping it true

- When a change moves a file, renames a symbol the wiki names, adds a tick
  system, a save version or a command, update the page that mentions it in the
  same commit.
- When you find debt, add a row to [tech-debt.md](tech-debt.md). When you pay
  some off, delete its row.
- Design decisions and balancing results belong in
  [Engine Architecture.md](<../Engine Architecture.md>), not here.

Written 2026-11-14, at commit `5a03209`.
