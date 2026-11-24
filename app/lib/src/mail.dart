import 'package:engine/engine.dart';
import 'package:flutter/widgets.dart';

import 'controller.dart';
import 'directors.dart';
import 'format.dart';
import 'l10n.dart';
import 'screens/sales_desk.dart' show openSalesDesk, openTendersFor;

/// The desk's mail, the owner's design of 2026-11-18: what waits on the
/// player, written by whoever runs the business it concerns, a CEO giving
/// their opinion; each with its numbers, how long it stands, what happens
/// without an answer, and the answers. Built afresh from the game: chains'
/// offers for shops across countries, rivals' offers for software, bids for
/// the player's shares or companies, and tenders their plants could win.

/// An answer to a mail: a command to give, or a page to open.
typedef MailAnswer = ({
  String label,
  Command? command,
  void Function(BuildContext context)? open,
});

/// One mail to the player.
final class Mail {
  const Mail({
    required this.key,
    required this.from,
    required this.subject,
    required this.paragraphs,
    this.fromLine,
    this.signature,
    this.lines = const [],
    this.until,
    this.fallback,
    this.answers = const [],
  });

  /// What it is about, unique among the mail.
  final String key;

  /// Who writes, and their title and character, if a person.
  final String from;
  final String? fromLine;
  final String subject;
  final List<String> paragraphs;

  /// How it is signed: the writer's first name, if a person.
  final String? signature;

  /// The numbers it rests on, label and value.
  final List<(String, String)> lines;

  /// The last day it stands, and what happens if the player doesn't answer.
  final Day? until;
  final String? fallback;
  final List<MailAnswer> answers;
}

/// Who writes for [company]: its CEO by name, with their title and
/// character, or the company itself.
({String from, String? line, String? signature, String? character}) mailSender(
  SimulationController game,
  CompanyView company,
) {
  final director = game.directorOf(company);
  final directors = game.content.directors;
  if (director == null || directors == null) {
    return (
      from: game.companyName(company.id),
      line: tr('mail.noCeo'),
      signature: null,
      character: null,
    );
  }
  final person = directorPerson(game, company, director);
  final grade = directors.grades[director.grade.index];
  return (
    from: person?.name ?? aDirector(grade),
    line: tr('mail.ceoOf', {
      'line': directorLine(game.content, grade, person),
      'company': game.companyName(company.id),
    }),
    signature: person?.name.split(' ').first,
    character: directors.characterOfPerson(person).key,
  );
}

/// What a CEO of [character] thinks of selling for [price] what is [worth]
/// to the company: take a price well over it, keep below it, and in between
/// as their character leans. Null without a CEO.
String? ceoOpinion(String? character, Money price, Money worth) {
  if (character == null) return null;
  if (worth <= Money.zero || price.cents * 100 >= worth.cents * 125) {
    return tr('mail.opinion.take');
  }
  if (price.cents * 100 < worth.cents * 95) return tr('mail.opinion.keep');
  return switch (character) {
    'bold' => tr('mail.opinion.fairBold'),
    'cautious' => tr('mail.opinion.fairCautious'),
    _ => tr('mail.opinion.fair'),
  };
}

/// Every mail waiting on the player, the soonest to lapse first.
List<Mail> mailOf(SimulationController game) {
  final view = game.view;
  final content = game.content;
  final mail = <Mail>[];
  final companies = {for (final c in game.activeCompanies) c.id: c};

  // Chains' offers for shops run by formula across a country.
  for (final country in view.national) {
    final id = country.country;
    if (id == null) continue;
    for (final offer in country.offers) {
      if (offer.block >= country.blocks.length) continue;
      final block = country.blocks[offer.block];
      final company = companies[block.company];
      if (company == null) continue;
      final sender = mailSender(game, company);
      final earned = block.value?.earnings ?? Money.zero;
      final worth = block.value?.price ?? Money.zero;
      final years = earned <= Money.zero
          ? null
          : (offer.price.cents / earned.cents).round();
      final countryName = content.countries[id.index].name;
      final price = compactMoney(offer.price);
      mail.add(
        Mail(
          key: 'chain ${id.index} ${offer.number}',
          from: sender.from,
          fromLine: sender.line,
          signature: sender.signature,
          subject: tr('mail.chainOffer.subject', {
            'chain': offer.chain,
            'price': price,
            'country': countryName,
          }),
          paragraphs: [
            tr(
              years == null
                  ? 'mail.chainOffer.bodyNoProfit'
                  : 'mail.chainOffer.body',
              {
                'chain': offer.chain,
                'count': block.stores,
                'country': countryName,
                'profit': compactMoney(earned),
                'years': ?years,
              },
            ),
            ?ceoOpinion(sender.character, offer.price, worth),
          ],
          lines: [
            (tr('mail.price'), money(offer.price, cents: false)),
            (tr('mail.theirProfit'), money(earned, cents: false)),
            (
              tr('mail.worthOf', {'company': game.companyName(company.id)}),
              _change(
                SimulationController.worthOf(company),
                SimulationController.worthOf(company) - worth + offer.price,
              ),
            ),
          ],
          until: offer.expires,
          fallback: _declines(sender.signature),
          answers: [
            (
              label: tr('mail.sellFor', {'price': price}),
              command: AcceptNationalOffer(game.player, offer: offer.number),
              open: null,
            ),
            (
              label: tr('mail.decline'),
              command: DeclineNationalOffer(game.player, offer: offer.number),
              open: null,
            ),
          ],
        ),
      );
    }
  }

  // Rivals' offers for software.
  for (final company in companies.values) {
    final software = company.software;
    final offer = software?.offer;
    if (software == null || offer == null) continue;
    final sender = mailSender(game, company);
    final worth = offer.whole ? software.worth.worth : software.worth.business;
    final price = compactMoney(offer.price);
    final companyName = game.companyName(company.id);
    mail.add(
      Mail(
        key: 'software ${software.id.index}',
        from: sender.from,
        fromLine: sender.line,
        signature: sender.signature,
        subject: tr('mail.softwareOffer.subject', {
          'rival': offer.rivalName,
          'price': price,
          'software': software.name,
        }),
        paragraphs: [
          tr(
            offer.whole
                ? 'mail.softwareOffer.whole'
                : 'mail.softwareOffer.alone',
            {
              'rival': offer.rivalName,
              'software': software.name,
              'company': companyName,
              'yours': compactMoney(offer.yours),
            },
          ),
          ?ceoOpinion(sender.character, offer.price, worth),
        ],
        lines: [
          (tr('mail.price'), money(offer.price, cents: false)),
          if (offer.whole) (tr('mail.yourShare'), money(offer.yours)),
          (tr('mail.itsWorth'), money(worth, cents: false)),
        ],
        until: offer.expires,
        fallback: _declines(sender.signature),
        answers: [
          (
            label: tr('mail.sellFor', {'price': price}),
            command: AcceptSoftwareOffer(game.player, software: software.id),
            open: null,
          ),
          (
            label: tr('mail.decline'),
            command: DeclineSoftwareOffer(game.player, software: software.id),
            open: null,
          ),
        ],
      ),
    );
  }

  // Bids for the player's companies or for shares they hold.
  if (view.stocks case final stocks?) {
    final mine = {for (final company in view.companies) company.id};
    bool concerns(StockView stock) =>
        (stock.company != null && mine.contains(stock.company)) ||
        stocks.holdings.any(
          (holding) => !holding.index && holding.of == stock.index,
        );
    for (final bid in stocks.bids) {
      if (bid.status != BidStatus.open ||
          isPlayers(bid.bidder) ||
          !concerns(stocks.stocks[bid.stock])) {
        continue;
      }
      final stock = stocks.stocks[bid.stock];
      final premium = bid.reference <= Money.zero
          ? 0
          : ((bid.price.cents - bid.reference.cents) *
                    100 /
                    bid.reference.cents)
                .round();
      final bidder = game.ownerName(bid.bidder);
      mail.add(
        Mail(
          key: 'bid ${bid.number}',
          from: tr('mail.exchange'),
          subject: tr('mail.bid.subject', {
            'bidder': bidder,
            'price': money(bid.price),
            'company': stock.name,
          }),
          paragraphs: [
            tr('mail.bid.body', {
              'bidder': bidder,
              'price': money(bid.price),
              'company': stock.name,
              'premium': premium,
            }),
          ],
          lines: [
            (tr('mail.pricePerShare'), money(bid.price)),
            (tr('mail.priceBefore'), money(bid.reference)),
          ],
          until: bid.closes,
          fallback: tr(bid.tender ? 'mail.bid.ifTendered' : 'mail.bid.ifNot'),
          answers: [
            (
              label: tr('mail.bid.tender'),
              command: AnswerBid(game.player, bid: bid.number, tender: true),
              open: null,
            ),
            (
              label: tr('mail.bid.keep'),
              command: AnswerBid(game.player, bid: bid.number, tender: false),
              open: null,
            ),
          ],
        ),
      );
    }
  }

  // Tenders the player's plants could win and haven't bid for.
  for (final (company, factory) in game.myFactories) {
    final sales = factory.sales;
    if (sales == null) continue;
    final sender = mailSender(game, company);
    for (final tender in openTendersFor(game, factory)) {
      if (tender.bidFactory != null) continue;
      final line = sales.lines
          .where((line) => line.product == tender.product)
          .firstOrNull;
      final price = line == null
          ? null
          : tenderBid(view.tenders, tender, line.unitCost);
      final bidText = price == null ? null : money(price);
      mail.add(
        Mail(
          key: 'tender ${tender.number} ${factory.id.index}',
          from: sender.from,
          fromLine: sender.line,
          signature: sender.signature,
          subject: tr('mail.tender.subject', {
            'chain': tender.chain,
            'units': tender.units,
            'months': tender.months,
          }),
          paragraphs: [
            tr('mail.tender.body', {
              'chain': tender.chain,
              'units': tender.units,
              'product': content.products[tender.product.index].name,
              'months': tender.months,
              'plant': factory.name,
            }),
            if (sender.character != null)
              tr(price == null ? 'mail.tender.noMargin' : 'mail.tender.bidAt', {
                'price': ?bidText,
              }),
          ],
          lines: [
            (tr('mail.producerPrice'), money(tender.reference)),
            if (line != null) (tr('mail.ourCost'), money(line.unitCost)),
          ],
          until: tender.closes,
          fallback: tr('mail.tender.ifNot', {'plant': factory.name}),
          answers: [
            if (price != null)
              (
                label: tr('mail.tender.bid', {'price': ?bidText}),
                command: BidTender(
                  game.player,
                  tender: tender.number,
                  factory: factory.id,
                  price: price,
                ),
                open: null,
              ),
            (
              label: tr('mail.tender.desk'),
              command: null,
              open: (context) => openSalesDesk(context, factory),
            ),
          ],
        ),
      );
    }
  }
  mail.sort(
    (a, b) =>
        (a.until?.number ?? 1 << 30).compareTo(b.until?.number ?? 1 << 30),
  );
  return mail;
}

/// What happens to an offer nobody answers: [signature]'s CEO declines it,
/// or it lapses.
String _declines(String? signature) => signature == null
    ? tr('mail.lapses')
    : tr('mail.declines', {'name': signature});

String _change(Money before, Money after) => tr('restructure.change', {
  'before': compactMoney(before),
  'after': compactMoney(after),
});
