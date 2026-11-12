import '../content/content_db.dart';
import '../core/fx.dart';
import '../core/ids.dart';
import '../persistence/state_io.dart';
import 'districts.dart';
import 'store.dart';
import 'world_state.dart';

/// A name its owner's shops of one type of business trade under: every shop
/// opened under it takes it, with its district, and starts as well known as
/// the brand's shops nearby. A brand belongs to a person, so any of their
/// companies may use it.
final class Brand {
  Brand({
    required this.id,
    required this.name,
    required this.format,
    required this.owner,
  });

  Brand.read(this.id, StateReader reader)
    : name = reader.readString(),
      format = FormatId(reader.readInt()),
      owner = PersonId(reader.readInt());

  final BrandId id;
  final String name;

  /// The one type of business it trades as.
  final FormatId format;
  final PersonId owner;

  void write(StateWriter writer) {
    writer
      ..writeString(name)
      ..writeInt(format.index)
      ..writeInt(owner.index);
  }
}

/// A brand as anyone sees it: its name is on the shop fronts.
typedef BrandView = ({
  BrandId id,
  String name,
  FormatId format,
  PersonId owner,

  /// Its shops trading or about to.
  int shops,
});

/// Whether [name] is some brand's already, whatever its case.
bool brandNameTaken(WorldState world, String name) {
  final wanted = name.trim().toLowerCase();
  return world.brands.any((brand) => brand.name.toLowerCase() == wanted);
}

/// Adds a brand for [owner].
Brand addBrand(WorldState world, String name, FormatId format, PersonId owner) {
  final brand = Brand(
    id: BrandId(world.brands.length),
    name: name.trim(),
    format: format,
    owner: owner,
  );
  world.brands.add(brand);
  return brand;
}

/// The district part of a market's name: "Part-Dieu" of "Lyon, Part-Dieu".
String _district(MarketDef market) {
  final comma = market.name.lastIndexOf(', ');
  return comma < 0 ? market.name : market.name.substring(comma + 2);
}

/// The city part of a market's name: "Lyon" of "Lyon, Part-Dieu".
String _city(MarketDef market) => cityOf(market.name);

/// The city part of a place's name: "Lyon" of "Lyon, Part-Dieu".
String cityOf(String name) {
  final comma = name.lastIndexOf(', ');
  return comma < 0 ? name : name.substring(0, comma);
}

/// The district part of a place's name: "Part-Dieu" of "Lyon, Part-Dieu".
String districtOf(String name) {
  final comma = name.lastIndexOf(', ');
  return comma < 0 ? name : name.substring(comma + 2);
}

/// What a shop of [brand] on [site] is called: the brand and its district,
/// and its street too if the brand already trades in that district.
String brandedName(
  WorldState world,
  ContentDb content,
  Brand brand,
  SiteDef site, {
  StoreId? except,
}) {
  final market = content.markets[site.market.index];
  final name = '${brand.name} ${_district(market)}';
  final twin = world.stores.any(
    (store) =>
        store.id != except &&
        store.brand == brand.id &&
        store.isTrading &&
        store.market == site.market,
  );
  return twin ? '$name, ${site.name}' : name;
}

/// How well known a new shop of [brand] in [market] starts: as its brand's
/// shops in the same city are, on average, or else its shops anywhere. Null
/// if the brand has none trading.
Fx? brandReputation(
  WorldState world,
  ContentDb content,
  Brand brand,
  MarketId market, {
  StoreId? except,
}) {
  final city = _city(content.markets[market.index]);
  var near = Fx.zero;
  var nearCount = 0;
  var all = Fx.zero;
  var allCount = 0;
  for (final store in world.stores) {
    if (store.id == except || store.brand != brand.id || !store.isTrading) {
      continue;
    }
    all += store.reputation;
    allCount++;
    if (_city(content.markets[store.market.index]) == city) {
      near += store.reputation;
      nearCount++;
    }
  }
  if (nearCount > 0) return Fx.raw(near.raw ~/ nearCount);
  if (allCount > 0) return Fx.raw(all.raw ~/ allCount);
  return null;
}

/// Puts [store] under [brand]: it takes the brand's name for its district,
/// and is at least as well known as the brand's shops nearby.
void brandStore(WorldState world, ContentDb content, Store store, Brand brand) {
  final site = content.sites[store.site.index];
  final known = brandReputation(
    world,
    content,
    brand,
    store.market,
    except: store.id,
  );
  store
    ..brand = brand.id
    ..name = brandedName(world, content, brand, site, except: store.id);
  if (known != null && known > store.reputation) store.reputation = known;
}

/// The brand an AI owner trades as for [format]: the one it has, or else a
/// new one named after [companyName], under which its shops of that type of
/// business then trade.
Brand aiBrand(
  WorldState world,
  ContentDb content,
  PersonId owner,
  FormatId format,
  String companyName,
) {
  for (final brand in world.brands) {
    if (brand.owner == owner && brand.format == format) return brand;
  }
  var name = companyName;
  if (brandNameTaken(world, name)) {
    name = '$companyName ${content.formats[format.index].name}';
  }
  for (var n = 2; brandNameTaken(world, name); n++) {
    name = '$companyName $n';
  }
  final brand = addBrand(world, name, format, owner);
  joinBrand(world, content, brand);
  return brand;
}

/// Puts every shop of [brand]'s owner and type of business that trades under
/// no brand yet under it, in the districts run by formula too: what starting
/// a brand does, for the player as for an AI owner.
void joinBrand(WorldState world, ContentDb content, Brand brand) {
  final owner = brand.owner;
  final format = brand.format;
  for (final store in world.stores) {
    if (store.isTrading &&
        store.format == format &&
        store.brand == null &&
        world.companies[store.company.index].owner == owner) {
      brandStore(world, content, store, brand);
    }
  }
  for (final sleeper in world.sleepers) {
    for (final shop in sleeper.shops) {
      final company = shop.company;
      if (company != null &&
          shop.format == format &&
          shop.brand == null &&
          world.companies[company.index].owner == owner) {
        shop
          ..brand = brand.id
          ..name = districtShopName(
            content,
            sleeper,
            brand,
            sitesOf(world, content, sleeper)[shop.site],
            except: shop,
          );
      }
    }
  }
}

/// [store], just come to [owner], under their brand if they're an AI owner;
/// a brand of the player's goes only where they put it.
void takeOverName(
  WorldState world,
  ContentDb content,
  Store store,
  PersonId owner,
) {
  if (owner == world.player) {
    store.brand = null;
    return;
  }
  final company = world.companies[store.company.index];
  final brand = aiBrand(world, content, owner, store.format, company.name);
  brandStore(world, content, store, brand);
}
