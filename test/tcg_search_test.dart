import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sist_flutter/main.dart';
import 'package:sist_flutter/scan_models.dart';

void main() {
  test('search treats ex as a card name, not a two-letter set hint', () async {
    final results = await _mockApi().searchPokemon('pikachu ex 238/191');

    expect(results, hasLength(1));
    expect(results.single.name, 'Pikachu ex - 238/191');
    expect(results.single.estimate, r'$337.11 market');
    expect(results.single.recordType, CardRecordType.lookup);
    expect(results.single.isLookup, isTrue);

    final stored = results.single.toJson();
    expect(stored['recordType'], 'lookup');
    expect(stored.containsKey('condition'), isFalse);
    expect(stored.containsKey('centering'), isFalse);
  });

  test('search finds a hyphenated card by collector number', () async {
    final results = await _mockApi().searchPokemon('Ho-Oh 001/025');

    expect(results, hasLength(1));
    expect(results.single.name, 'Ho-Oh');
    expect(results.single.number, '001/025');
  });

  test('search finds VSTAR cards when words are reversed', () async {
    final results = await _mockApi().searchPokemon('vstar arceus');

    expect(results.first.name, 'Arceus VSTAR');
  });

  test('sample passport keeps scan-only condition fields in storage', () {
    final passport = CardPassport.sample();
    final stored = passport.toJson();

    expect(passport.recordType, CardRecordType.passport);
    expect(stored['recordType'], 'passport');
    expect(stored.containsKey('condition'), isTrue);
    expect(stored.containsKey('centering'), isTrue);
  });

  test('scan candidates hydrate market value from raw product payload', () {
    final candidate = CardCandidate.fromJson({
      'id': '676089',
      'name': 'Pikachu ex - 277/217',
      'set_name': 'ME: Ascended Heroes',
      'card_number': '277/217',
      'image_url':
          'https://tcgplayer-cdn.tcgplayer.com/product/676089_200w.jpg',
      'confidence': 72,
      'raw': {
        'product_id': 676089,
        'market_price': '465.85',
        'ext_rarity': 'Special Illustration Rare',
        'ext_number': '277/217',
      },
    });

    final passport = const PassportDataService().createPassportFromBackend(
      candidate: candidate,
      rectifiedImageBase64: 'abc123',
    );

    expect(candidate.marketValue, r'$465.85 market');
    expect(candidate.rarity, 'Special Illustration Rare');
    expect(passport.marketValue, r'$465.85 market');
    expect(passport.rarity, 'Special Illustration Rare');
  });
}

TcgTrackingApi _mockApi() {
  return TcgTrackingApi(
    client: MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/3/sets')) {
        return _jsonResponse({
          'sets': [
            _set(10, 'Example Set', 'EX', '2025-01-01'),
            _set(23651, 'SV08: Surging Sparks', 'SSP', '2024-11-08'),
            _set(2948, 'SWSH09: Brilliant Stars', 'SWSH09', '2022-02-25'),
            _set(1234, 'POP Series 5', 'POP5', '2022-01-01'),
            _set(2867, 'Celebrations', 'CLB', '2021-10-08'),
          ],
        });
      }

      if (path.endsWith('/3/sets/10')) {
        return _jsonResponse({'products': []});
      }

      if (path.endsWith('/3/sets/23651')) {
        return _jsonResponse({
          'products': [
            _product(
              590027,
              'Pikachu ex - 238/191',
              'Pikachu ex 238 191',
              '238/191',
              'Special Illustration Rare',
            ),
          ],
        });
      }

      if (path.endsWith('/3/sets/2948')) {
        return _jsonResponse({
          'products': [
            _product(
              257279,
              'Arceus VSTAR',
              'Arceus VSTAR',
              '123/172',
              'Ultra Rare',
            ),
            _product(
              123456,
              'Arceus VSTAR - 123/172 (Metal Card)',
              'Arceus VSTAR 123 172 Metal Card',
              '123/172',
              'Promo',
            ),
          ],
        });
      }

      if (path.endsWith('/3/sets/2867')) {
        return _jsonResponse({
          'products': [
            _product(250300, 'Ho-Oh', 'Ho Oh', '001/025', 'Holo Rare'),
          ],
        });
      }

      if (path.endsWith('/3/sets/1234')) {
        return _jsonResponse({
          'products': [
            _product(250301, 'Ho-Oh', 'Ho Oh', '001/017', 'Holo Rare'),
          ],
        });
      }

      if (path.endsWith('/pricing')) {
        return _jsonResponse({
          'prices': {
            '590027': {
              'tcg': {
                'Holofoil': {'low': 310, 'market': 337.11},
              },
            },
            '257279': {
              'tcg': {
                'Holofoil': {'low': 8, 'market': 10.25},
              },
            },
            '123456': {
              'tcg': {
                'Holofoil': {'low': 4, 'market': 5.25},
              },
            },
            '250300': {
              'tcg': {
                'Holofoil': {'low': 0.5, 'market': 1.2},
              },
            },
            '250301': {
              'tcg': {
                'Holofoil': {'low': 40, 'market': 41.96},
              },
            },
          },
        });
      }

      return http.Response('Not found', 404);
    }),
  );
}

Map<String, Object?> _set(
  int id,
  String name,
  String abbreviation,
  String publishedOn,
) {
  return {
    'id': id,
    'name': name,
    'abbreviation': abbreviation,
    'published_on': publishedOn,
    'product_count': 1,
  };
}

Map<String, Object?> _product(
  int id,
  String name,
  String cleanName,
  String number,
  String rarity,
) {
  return {
    'id': id,
    'name': name,
    'clean_name': cleanName,
    'number': number,
    'rarity': rarity,
    'image_url': 'https://example.com/$id.jpg',
  };
}

http.Response _jsonResponse(Map<String, Object?> data) {
  return http.Response(
    jsonEncode(data),
    200,
    headers: {'content-type': 'application/json'},
  );
}
