import 'package:engine/engine.dart';
import 'package:flutter/material.dart';

import '../format.dart';
import '../l10n.dart';
import '../theme.dart';
import '../widgets.dart';

/// Sets up a new game: the company's name, the city, the site and the kind
/// of business of the first store. Returns the [GameStart] chosen, or null
/// if the player goes back.
class NewGameScreen extends StatefulWidget {
  const NewGameScreen({super.key, required this.content});

  final ContentDb content;

  @override
  State<NewGameScreen> createState() => _NewGameScreenState();
}

class _NewGameScreenState extends State<NewGameScreen> {
  ContentDb get _content => widget.content;
  late final List<SiteId> _sites = startingSites(_content);
  late final _name = TextEditingController(text: _usual.name);
  late MarketId _market = _content.sites[_usual.site.index].market;
  late SiteId _site = _usual.site;
  late FormatId _format = _usual.format;

  /// The scenario's own first store for the player.
  StoreSetup get _usual => _content.stores.firstWhere(
    (store) => _content.companies[store.company.index].owner == _content.player,
  );

  /// What fitting out [site] for [format] costs.
  Money _fitOut(SiteDef site, FormatDef format) =>
      site.openingCost.times(format.fitOut);

  /// The most fitting out may cost: what the scenario's first store cost,
  /// the company's and the player's cash, less what the company keeps.
  Money get _budget {
    final usual = _usual;
    return _fitOut(
          _content.sites[usual.site.index],
          _content.formats[usual.format.index],
        ) +
        _content.companies[usual.company.index].cash +
        _content.persons[_content.player.index].cash -
        minStartingCash;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  GameStart get _start =>
      GameStart(site: _site, format: _format, name: _name.text.trim());

  void _pickMarket(MarketId market) {
    final sites = _sitesIn(market);
    setState(() {
      _market = market;
      if (!sites.contains(_site)) _pickSite(sites.first);
    });
  }

  void _pickSite(SiteId site) {
    _site = site;
    final area = _content.sites[site.index].area;
    if (_content.formats[_format.index].minArea > area) {
      _format = _content.formats.first.id;
    }
  }

  List<SiteId> _sitesIn(MarketId market) => [
    for (final site in _sites)
      if (_content.sites[site.index].market == market) site,
  ];

  /// The scenario's stores in [market] that compete with [format] at the
  /// start.
  int _rivals(MarketId market, FormatId format) {
    final channel = _content.formatChannels[format.index];
    final usual = _usual;
    return _content.stores
        .where(
          (store) =>
              !identical(store, usual) &&
              _content.sites[store.site.index].market == market &&
              _content.formatChannels[store.format.index] == channel,
        )
        .length;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final market = _content.markets[_market.index];
    final site = _content.sites[_site.index];
    final format = _content.formats[_format.index];
    final (terms, problem) = startTerms(_content, _start);
    final households = market.households.fold(0, (sum, n) => sum + n);
    return Scaffold(
      appBar: AppBar(title: Text(tr('common.newGame'))),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 6),
        children: [
          Section(
            title: tr('newGame.yourCompany'),
            icon: Icons.badge_outlined,
            children: [
              TextField(
                controller: _name,
                maxLength: maxNameLength,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(labelText: tr('newGame.nameLabel')),
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
          Section(
            title: tr('newGame.city'),
            icon: Icons.location_city_outlined,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final city in _content.markets)
                    if (_sitesIn(city.id).isNotEmpty)
                      ChoiceChip(
                        label: Text(city.name),
                        selected: city.id == _market,
                        onSelected: (_) => _pickMarket(city.id),
                      ),
                ],
              ),
              const SizedBox(height: 6),
              Hint(
                tr('newGame.cityHint', {
                  'households': households,
                  'prices': percent(market.priceLevel, decimals: 0),
                  'incomes': percent(market.incomeLevel, decimals: 0),
                  'wages': percent(market.wageLevel, decimals: 0),
                }),
              ),
            ],
          ),
          Section(
            title: tr('newGame.site'),
            icon: Icons.place_outlined,
            children: [
              for (final id in _sitesIn(_market))
                _SiteTile(
                  site: _content.sites[id.index],
                  fitOut:
                      _content.formats[_format.index].minArea >
                          _content.sites[id.index].area
                      ? null
                      : _fitOut(_content.sites[id.index], format),
                  budget: _budget,
                  selected: id == _site,
                  onTap: () => setState(() => _pickSite(id)),
                ),
            ],
          ),
          Section(
            title: tr('newGame.business'),
            icon: formatIcon(format),
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final kind in _content.formats)
                    if (kind.minArea <= site.area)
                      ChoiceChip(
                        avatar: Icon(formatIcon(kind), size: 18),
                        label: Text(kind.name),
                        selected: kind.id == _format,
                        onSelected: (_) => setState(() => _format = kind.id),
                      ),
                ],
              ),
              const SizedBox(height: 6),
              Hint(
                trMaybe('scenario.formats.${format.key}.blurb') ?? format.name,
              ),
              Hint(tr('newGame.rivals', {'count': _rivals(_market, _format)})),
            ],
          ),
          Section(
            title: tr('newGame.startingOut'),
            icon: Icons.account_balance_wallet_outlined,
            children: [
              if (terms != null) ...[
                Line(
                  tr('common.fittingOut'),
                  money(terms.fitOut, cents: false),
                ),
                Line(
                  tr('newGame.companyCash'),
                  money(terms.companyCash, cents: false),
                  strong: true,
                ),
                Line(
                  tr('common.ownCash'),
                  money(terms.personalCash, cents: false),
                ),
                Hint(
                  terms.capital > Money.zero
                      ? tr('newGame.capitalIn', {
                          'capital': money(terms.capital, cents: false),
                          'cash': money(minStartingCash, cents: false),
                        })
                      : tr('newGame.wellOff'),
                ),
              ] else
                Text(
                  _fitOut(site, format) > _budget
                      ? tr('newGame.tooDear', {
                          'format': format.name,
                          'cost': money(_fitOut(site, format), cents: false),
                          'budget': money(_budget, cents: false),
                          'keep': money(minStartingCash, cents: false),
                        })
                      : '${capitalized(refusalText(problem!, _content))}.',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: FilledButton.icon(
              icon: const Icon(Icons.play_arrow),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              onPressed: terms == null
                  ? null
                  : () => Navigator.of(context).pop(_start),
              label: Text(tr('newGame.start')),
            ),
          ),
        ],
      ),
    );
  }
}

class _SiteTile extends StatelessWidget {
  const _SiteTile({
    required this.site,
    required this.fitOut,
    required this.budget,
    required this.selected,
    required this.onTap,
  });

  final SiteDef site;

  /// Fitting it out for the business picked; null if it is too small.
  final Money? fitOut;

  /// The most fitting out may cost.
  final Money budget;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      elevation: 0,
      color: selected
          ? theme.colorScheme.primaryContainer
          : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      child: ListTile(
        dense: true,
        onTap: onTap,
        leading: Icon(
          selected ? Icons.radio_button_checked : Icons.radio_button_off,
          color: selected ? theme.colorScheme.primary : null,
        ),
        title: Text(site.name),
        subtitle: Text.rich(
          TextSpan(
            text: tr('newGame.siteDetails', {
              'area': site.area,
              'rent': money(site.rent, cents: false),
              'location': percent(site.location, decimals: 0),
            }),
            children: [
              TextSpan(
                text: switch (fitOut) {
                  final cost? => tr('newGame.fittingOutCost', {
                    'cost': money(cost, cents: false),
                  }),
                  null => tr('newGame.tooSmall'),
                },
                style: TextStyle(
                  color: fitOut == null || fitOut! > budget
                      ? theme.colorScheme.error
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
