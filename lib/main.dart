import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'binder_repository.dart';
import 'scan_api_client.dart';
import 'scan_models.dart';

void main() {
  runApp(const ShouldISlabThisApp());
}

class ShouldISlabThisApp extends StatelessWidget {
  const ShouldISlabThisApp({this.samplePassportLoader, super.key});

  final Future<CardPassport> Function()? samplePassportLoader;

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF121342);
    const violet = Color(0xFF4B1DFF);

    return MaterialApp(
      title: 'Should I Slab This',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: violet,
          brightness: Brightness.light,
        ),
        fontFamily: 'SF Pro Display',
        scaffoldBackgroundColor: const Color(0xFFFBFAFF),
        textTheme: Theme.of(
          context,
        ).textTheme.apply(bodyColor: ink, displayColor: ink),
      ),
      builder: (context, child) {
        return CupertinoTheme(
          data: const CupertinoThemeData(
            primaryColor: Color(0xFF4B1DFF),
            scaffoldBackgroundColor: Color(0xFFF7F7FB),
            textTheme: CupertinoTextThemeData(
              primaryColor: Color(0xFF11123E),
              textStyle: TextStyle(
                color: Color(0xFF11123E),
                fontFamily: '.SF Pro Text',
                fontSize: 16,
              ),
            ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: HomeShell(samplePassportLoader: samplePassportLoader),
    );
  }
}

class CardCondition {
  const CardCondition({required this.grade, required this.label});

  factory CardCondition.fromJson(Map<String, dynamic> json) {
    return CardCondition(
      grade: json['grade'] as String? ?? 'TBD',
      label: json['label'] as String? ?? 'Needs scan',
    );
  }

  final String grade;
  final String label;

  Map<String, Object?> toJson() {
    return {'grade': grade, 'label': label};
  }
}

class CenteringTier {
  const CenteringTier({
    required this.grade,
    required this.label,
    required this.displayLabel,
    required this.description,
    this.tiltAffected = false,
  });

  final String grade;
  final String label;
  final String displayLabel;
  final String description;
  final bool tiltAffected;
}

class CardCentering {
  const CardCentering({
    required this.topBottom,
    required this.leftRight,
    required this.tilt,
  });

  factory CardCentering.fromJson(Map<String, dynamic> json) {
    return CardCentering(
      topBottom: json['topBottom'] as String? ?? '--',
      leftRight: json['leftRight'] as String? ?? '--',
      tilt: json['tilt'] as String? ?? '--',
    );
  }

  final String topBottom;
  final String leftRight;
  final String tilt;

  Map<String, Object?> toJson() {
    return {'topBottom': topBottom, 'leftRight': leftRight, 'tilt': tilt};
  }

  CenteringTier get tier => centeringTierFor(this);
}

CenteringTier centeringTierFor(CardCentering centering) {
  final topBottom = _parseRatio(centering.topBottom);
  final leftRight = _parseRatio(centering.leftRight);
  final tilt = _parseTiltDegrees(centering.tilt);
  if (topBottom == null || leftRight == null || tilt == null) {
    return _tierForGrade('D');
  }

  final topBottomMax = math.max(topBottom.$1, topBottom.$2);
  final leftRightMax = math.max(leftRight.$1, leftRight.$2);
  final absoluteTilt = tilt.abs();
  final grade = _gradeForCentering(
    topBottomMax: topBottomMax,
    leftRightMax: leftRightMax,
    absoluteTilt: absoluteTilt,
  );
  final gradeWithoutTilt = _gradeForCentering(
    topBottomMax: topBottomMax,
    leftRightMax: leftRightMax,
    absoluteTilt: 0,
  );
  return _tierForGrade(
    grade,
    tiltAffected: _tierRank(grade) > _tierRank(gradeWithoutTilt),
  );
}

(double, double)? _parseRatio(String value) {
  final parts = value.split('/');
  if (parts.length != 2) {
    return null;
  }
  final first = double.tryParse(parts[0].trim());
  final second = double.tryParse(parts[1].trim());
  if (first == null || second == null) {
    return null;
  }
  return (first, second);
}

double? _parseTiltDegrees(String value) {
  final cleaned = value.replaceAll(RegExp(r'[^0-9.\-]'), '').trim();
  return double.tryParse(cleaned);
}

String _gradeForCentering({
  required double topBottomMax,
  required double leftRightMax,
  required double absoluteTilt,
}) {
  if (topBottomMax <= 51 && leftRightMax <= 51 && absoluteTilt <= 0.3) {
    return 'S';
  }
  if (topBottomMax <= 55 && leftRightMax <= 55 && absoluteTilt <= 1.0) {
    return 'A';
  }
  if (topBottomMax <= 60 && leftRightMax <= 60 && absoluteTilt <= 1.5) {
    return 'B';
  }
  if (topBottomMax <= 70 && leftRightMax <= 70 && absoluteTilt <= 3.0) {
    return 'C';
  }
  return 'D';
}

CenteringTier _tierForGrade(String grade, {bool tiltAffected = false}) {
  return switch (grade.toUpperCase()) {
    'S' => CenteringTier(
      grade: 'S',
      label: 'Supreme',
      displayLabel: 'S — Supreme',
      tiltAffected: tiltAffected,
      description:
          'Dead-centered front. Black label potential centering, assuming the rest of the card is flawless.',
    ),
    'A' => CenteringTier(
      grade: 'A',
      label: 'Awesome',
      displayLabel: 'A — Awesome',
      tiltAffected: tiltAffected,
      description:
          'Great centering. Within PSA 10 centering range, but corners, edges, surface, and print quality still matter.',
    ),
    'B' => CenteringTier(
      grade: 'B',
      label: 'Bravo',
      displayLabel: 'B — Bravo',
      tiltAffected: tiltAffected,
      description:
          'Strong binder centering. It may still grade well, but centering is more likely to cap it below a 10.',
    ),
    'C' => CenteringTier(
      grade: 'C',
      label: 'Cool',
      displayLabel: 'C — Cool',
      tiltAffected: tiltAffected,
      description:
          'Looks good in a binder, but the centering is visibly off for grading.',
    ),
    _ => CenteringTier(
      grade: 'D',
      label: 'Dank',
      displayLabel: 'D — Dank',
      tiltAffected: tiltAffected,
      description:
          'A wild miscut appears. This is off-center enough to treat as a potential miscut/OC card.',
    ),
  };
}

int _tierRank(String grade) {
  return switch (grade.toUpperCase()) {
    'S' => 0,
    'A' => 1,
    'B' => 2,
    'C' => 3,
    _ => 4,
  };
}

enum CardRecordType {
  lookup('lookup', 'Lookup'),
  passport('passport', 'Passport');

  const CardRecordType(this.storageValue, this.label);

  final String storageValue;
  final String label;

  static CardRecordType fromStorage(
    Object? value, {
    required CardCondition condition,
    required CardCentering centering,
  }) {
    final normalized = value?.toString().toLowerCase().trim();
    if (normalized == lookup.storageValue) {
      return lookup;
    }
    if (normalized == passport.storageValue) {
      return passport;
    }

    final hasScanCondition =
        condition.grade != 'TBD' || condition.label != 'Needs scan';
    final hasCentering =
        centering.topBottom != '--' ||
        centering.leftRight != '--' ||
        centering.tilt != '--';
    return hasScanCondition || hasCentering ? passport : lookup;
  }
}

typedef ScanLauncher = Future<void> Function({CardPassport? sourceLookup});
typedef SamplePassportLoader = Future<CardPassport> Function();

const samplePikachuAssetPath = 'assets/samples/pika.png';

class CardPassport {
  CardPassport({
    required this.id,
    this.recordType = CardRecordType.passport,
    this.cardId,
    this.externalApiId,
    this.productId,
    required this.name,
    required this.set,
    required this.number,
    required this.year,
    required this.marketValue,
    required this.condition,
    required this.centering,
    required this.createdAt,
    required this.updatedAt,
    this.imageUrl,
    this.localImageKey,
    this.localThumbnailKey,
    this.originalScanImageKey,
    this.rectifiedScanImageKey,
    this.scannedImageBase64,
    this.shareImageBase64,
    this.rarity,
    this.marketSubtype,
    this.tcgplayerUrl,
    this.source,
    this.confidenceLabel,
    this.tintValue = 0xFF4B1DFF,
  });

  factory CardPassport.sample() {
    final now = DateTime.now();
    return CardPassport(
      id: 'sample-pikachu-ex-277-217',
      recordType: CardRecordType.passport,
      externalApiId: '676089',
      productId: 676089,
      name: 'Pikachu ex - 277/217',
      set: 'ME: Ascended Heroes',
      number: '277/217',
      year: '2026',
      marketValue: '\$465.85 market',
      imageUrl: 'https://tcgplayer-cdn.tcgplayer.com/product/676089_200w.jpg',
      rarity: 'Special Illustration Rare',
      marketSubtype: 'Holofoil',
      tcgplayerUrl:
          'https://www.tcgplayer.com/product/676089/pokemon-me-ascended-heroes-pikachu-ex-277-217',
      condition: const CardCondition(grade: 'S', label: 'Supreme'),
      centering: const CardCentering(
        topBottom: '46/54',
        leftRight: '46/54',
        tilt: '0.1%',
      ),
      source: 'Live sample scan',
      confidenceLabel: 'High',
      tintValue: 0xFF4B1DFF,
      createdAt: now,
      updatedAt: now,
    );
  }

  factory CardPassport.samplePikachuLookup() {
    final now = DateTime.now();
    return CardPassport(
      id: 'tcg-676089',
      recordType: CardRecordType.lookup,
      externalApiId: '676089',
      productId: 676089,
      name: 'Pikachu ex - 277/217',
      set: 'ME: Ascended Heroes',
      number: '277/217',
      year: '2026',
      marketValue: '\$465.85 market',
      imageUrl: 'https://tcgplayer-cdn.tcgplayer.com/product/676089_200w.jpg',
      rarity: 'Special Illustration Rare',
      marketSubtype: 'Holofoil',
      tcgplayerUrl:
          'https://www.tcgplayer.com/product/676089/pokemon-me-ascended-heroes-pikachu-ex-277-217',
      source: 'Live TCG Tracking',
      confidenceLabel: 'Known sample card',
      condition: const CardCondition(grade: 'TBD', label: 'Needs scan'),
      centering: const CardCentering(
        topBottom: '--',
        leftRight: '--',
        tilt: '--',
      ),
      tintValue: 0xFF4B1DFF,
      createdAt: now,
      updatedAt: now,
    );
  }

  factory CardPassport.fromJson(Map<String, dynamic> json) {
    final conditionJson = json['condition'] as Map<String, dynamic>?;
    final centeringJson = json['centering'] as Map<String, dynamic>?;
    final condition = conditionJson == null
        ? const CardCondition(grade: 'TBD', label: 'Needs scan')
        : CardCondition.fromJson(conditionJson);
    final centering = centeringJson == null
        ? const CardCentering(topBottom: '--', leftRight: '--', tilt: '--')
        : CardCentering.fromJson(centeringJson);
    return CardPassport(
      id: json['id'] as String? ?? json['externalApiId']?.toString() ?? '',
      recordType: CardRecordType.fromStorage(
        json['recordType'] ?? json['type'],
        condition: condition,
        centering: centering,
      ),
      cardId: json['cardId'] as String?,
      externalApiId: json['externalApiId'] as String?,
      productId: json['productId'] as int?,
      name: json['name'] as String? ?? 'Unknown Card',
      set: json['set'] as String? ?? 'Unknown Set',
      number: json['number'] as String? ?? 'No number',
      year: json['year'] as String? ?? 'Unknown year',
      marketValue:
          json['marketValue'] as String? ??
          json['estimate'] as String? ??
          'Market unavailable',
      imageUrl: json['imageUrl'] as String?,
      localImageKey: json['localImageKey'] as String?,
      localThumbnailKey: json['localThumbnailKey'] as String?,
      originalScanImageKey: json['originalScanImageKey'] as String?,
      rectifiedScanImageKey: json['rectifiedScanImageKey'] as String?,
      scannedImageBase64: json['scannedImageBase64'] as String?,
      shareImageBase64: json['shareImageBase64'] as String?,
      rarity: json['rarity'] as String?,
      marketSubtype: json['marketSubtype'] as String?,
      tcgplayerUrl: json['tcgplayerUrl'] as String?,
      source: json['source'] as String?,
      confidenceLabel:
          json['confidenceLabel'] as String? ?? json['confidence'] as String?,
      condition: condition,
      centering: centering,
      tintValue: json['tintValue'] as int? ?? 0xFF4B1DFF,
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  final String id;
  final CardRecordType recordType;
  final String? cardId;
  final String? externalApiId;
  final int? productId;
  final String name;
  final String set;
  final String number;
  final String year;
  final String marketValue;
  final String? imageUrl;
  final String? localImageKey;
  final String? localThumbnailKey;
  final String? originalScanImageKey;
  final String? rectifiedScanImageKey;
  final String? scannedImageBase64;
  final String? shareImageBase64;
  final String? rarity;
  final String? marketSubtype;
  final String? tcgplayerUrl;
  final String? source;
  final String? confidenceLabel;
  final CardCondition condition;
  final CardCentering centering;
  final int tintValue;
  final DateTime createdAt;
  final DateTime updatedAt;

  String get estimate => marketValue;
  String get gradePotential => condition.label;
  String get confidence => source ?? confidenceLabel ?? 'Unknown source';
  bool get isPassport => recordType == CardRecordType.passport;
  bool get isLookup => recordType == CardRecordType.lookup;
  bool get hasLookupMetadata {
    return source != null || marketSubtype != null || productId != null;
  }

  Color get tint => Color(tintValue);

  CardPassport copyWith({
    String? id,
    CardRecordType? recordType,
    String? cardId,
    String? externalApiId,
    int? productId,
    String? name,
    String? set,
    String? number,
    String? year,
    String? marketValue,
    String? imageUrl,
    String? localImageKey,
    String? localThumbnailKey,
    String? originalScanImageKey,
    String? rectifiedScanImageKey,
    String? scannedImageBase64,
    String? shareImageBase64,
    String? rarity,
    String? marketSubtype,
    String? tcgplayerUrl,
    String? source,
    String? confidenceLabel,
    CardCondition? condition,
    CardCentering? centering,
    int? tintValue,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CardPassport(
      id: id ?? this.id,
      recordType: recordType ?? this.recordType,
      cardId: cardId ?? this.cardId,
      externalApiId: externalApiId ?? this.externalApiId,
      productId: productId ?? this.productId,
      name: name ?? this.name,
      set: set ?? this.set,
      number: number ?? this.number,
      year: year ?? this.year,
      marketValue: marketValue ?? this.marketValue,
      imageUrl: imageUrl ?? this.imageUrl,
      localImageKey: localImageKey ?? this.localImageKey,
      localThumbnailKey: localThumbnailKey ?? this.localThumbnailKey,
      originalScanImageKey: originalScanImageKey ?? this.originalScanImageKey,
      rectifiedScanImageKey:
          rectifiedScanImageKey ?? this.rectifiedScanImageKey,
      scannedImageBase64: scannedImageBase64 ?? this.scannedImageBase64,
      shareImageBase64: shareImageBase64 ?? this.shareImageBase64,
      rarity: rarity ?? this.rarity,
      marketSubtype: marketSubtype ?? this.marketSubtype,
      tcgplayerUrl: tcgplayerUrl ?? this.tcgplayerUrl,
      source: source ?? this.source,
      confidenceLabel: confidenceLabel ?? this.confidenceLabel,
      condition: condition ?? this.condition,
      centering: centering ?? this.centering,
      tintValue: tintValue ?? this.tintValue,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'recordType': recordType.storageValue,
      'cardId': cardId,
      'externalApiId': externalApiId,
      'productId': productId,
      'name': name,
      'set': set,
      'number': number,
      'year': year,
      'marketValue': marketValue,
      'imageUrl': imageUrl,
      'localImageKey': localImageKey,
      'localThumbnailKey': localThumbnailKey,
      'originalScanImageKey': originalScanImageKey,
      'rectifiedScanImageKey': rectifiedScanImageKey,
      'scannedImageBase64': scannedImageBase64,
      'shareImageBase64': shareImageBase64,
      'rarity': rarity,
      'marketSubtype': marketSubtype,
      'tcgplayerUrl': tcgplayerUrl,
      'source': source,
      'confidenceLabel': confidenceLabel,
      if (isPassport) 'condition': condition.toJson(),
      if (isPassport) 'centering': centering.toJson(),
      'tintValue': tintValue,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }
}

class PassportDataService {
  const PassportDataService();

  Future<CardPassport> getSamplePassport() async {
    return CardPassport.sample();
  }

  Future<CardPassport> createPassportFromScan({
    CardPassport? sourceLookup,
  }) async {
    final sample = CardPassport.sample();
    if (sourceLookup == null) {
      return sample;
    }

    final now = DateTime.now();
    return CardPassport(
      id: uniqueId('passport-${passportIdentity(sourceLookup)}'),
      recordType: CardRecordType.passport,
      cardId: sourceLookup.cardId,
      externalApiId: sourceLookup.externalApiId,
      productId: sourceLookup.productId,
      name: sourceLookup.name,
      set: sourceLookup.set,
      number: sourceLookup.number,
      year: sourceLookup.year,
      marketValue: sourceLookup.marketValue,
      imageUrl: sourceLookup.imageUrl,
      rarity: sourceLookup.rarity,
      marketSubtype: sourceLookup.marketSubtype,
      tcgplayerUrl: sourceLookup.tcgplayerUrl,
      source: 'Scan placeholder',
      confidenceLabel: 'Awaiting real grading pipeline',
      condition: sample.condition,
      centering: sample.centering,
      tintValue: sourceLookup.tintValue,
      createdAt: now,
      updatedAt: now,
    );
  }

  CardPassport createPassportFromBackend({
    CardPassport? sourceLookup,
    CardCandidate? candidate,
    required String rectifiedImageBase64,
    CenteringAnalysis? centering,
  }) {
    final now = DateTime.now();
    final name = sourceLookup?.name ?? candidate?.name ?? 'Unknown Card';
    final set = sourceLookup?.set ?? candidate?.setName ?? 'Unknown Set';
    final number = sourceLookup?.number ?? candidate?.cardNumber ?? 'No number';
    final productId = int.tryParse(
      sourceLookup?.externalApiId ?? candidate?.id ?? '',
    );
    final cardCentering = CardCentering(
      topBottom: centering?.topBottom ?? '--',
      leftRight: centering?.leftRight ?? '--',
      tilt: centering == null
          ? '--'
          : '${centering.tiltPercent.toStringAsFixed(1)}%',
    );
    final tier = cardCentering.tier;

    return CardPassport(
      id: uniqueId('passport-${normalizeForSearch('$name-$number')}'),
      recordType: CardRecordType.passport,
      cardId: sourceLookup?.cardId,
      externalApiId: sourceLookup?.externalApiId ?? candidate?.id,
      productId: sourceLookup?.productId ?? productId,
      name: name,
      set: set,
      number: number,
      year: sourceLookup?.year ?? 'Unknown year',
      marketValue:
          sourceLookup?.marketValue ??
          candidate?.marketValue ??
          'Market unavailable',
      imageUrl: sourceLookup?.imageUrl ?? candidate?.imageUrl,
      scannedImageBase64: rectifiedImageBase64,
      rarity: sourceLookup?.rarity ?? candidate?.rarity,
      marketSubtype: sourceLookup?.marketSubtype,
      tcgplayerUrl: sourceLookup?.tcgplayerUrl,
      source: 'Scanned card',
      confidenceLabel: centering?.confidence ?? 'Backend scan',
      condition: CardCondition(grade: tier.grade, label: tier.label),
      centering: cardCentering,
      tintValue: sourceLookup?.tintValue ?? 0xFF4B1DFF,
      createdAt: now,
      updatedAt: now,
    );
  }
}

String centeringLabelForRank(String rank) {
  return switch (rank.toUpperCase()) {
    'S' => 'Supreme',
    'A' => 'Awesome',
    'B' => 'Bravo',
    'C' => 'Cool',
    'D' => 'Dank',
    _ => 'Centering Check',
  };
}

final List<CardPassport> dummyPassports = [CardPassport.sample()];

CardBoundary samplePikachuBoundary() {
  return CardBoundary.fromCorners(
    topLeft: const BoundaryPoint(x: 183.0, y: 290.4789123535156),
    topRight: const BoundaryPoint(x: 829.8284912109375, y: 295.4354553222656),
    bottomRight: const BoundaryPoint(x: 819.7543334960938, y: 1202.10888671875),
    bottomLeft: const BoundaryPoint(x: 183.0, y: 1191.8387451171875),
    imageWidth: 1080,
    imageHeight: 1440,
    segmentationConfidence: 0.78125,
    cardAreaRatio: 0.37309,
  );
}

class BinderCard {
  BinderCard({
    required this.passport,
    required this.addedAt,
    String? localId,
    this.schemaVersion = binderSchemaVersion,
    this.collectionType = 'binder',
    this.notes,
  }) : localId = localId ?? passportIdentity(passport);

  factory BinderCard.fromJson(Map<String, dynamic> json) {
    final passportJson = json['passport'];
    final passport = passportJson is Map<String, dynamic>
        ? CardPassport.fromJson(passportJson)
        : CardPassport.fromJson(json);
    return BinderCard(
      passport: passport,
      addedAt:
          DateTime.tryParse(
            json['addedAt'] as String? ?? json['savedAt'] as String? ?? '',
          ) ??
          DateTime.now(),
      localId:
          json['localId'] as String? ??
          json['id'] as String? ??
          passportIdentity(passport),
      schemaVersion:
          (json['schemaVersion'] as num?)?.toInt() ?? binderSchemaVersion,
      collectionType: json['collectionType'] as String? ?? 'binder',
      notes: json['notes'] as String?,
    );
  }

  final String localId;
  final int schemaVersion;
  final CardPassport passport;
  final DateTime addedAt;
  final String collectionType;
  final String? notes;

  String get id => localId;

  Map<String, Object?> toJson() {
    final tier = passport.centering.tier;
    final topBottom = _parseRatio(passport.centering.topBottom);
    final leftRight = _parseRatio(passport.centering.leftRight);
    final tilt = _parseTiltDegrees(passport.centering.tilt);
    return {
      'localId': localId,
      'schemaVersion': schemaVersion,
      'cardId': passport.cardId ?? passport.externalApiId,
      'name': passport.name,
      'setName': passport.set,
      'setId': passport.productId?.toString(),
      'number': passport.number,
      'rarity': passport.rarity,
      'imageUrl': passport.imageUrl,
      'localImageKey': passport.localImageKey,
      'localThumbnailKey': passport.localThumbnailKey,
      'originalScanImageKey': passport.originalScanImageKey,
      'rectifiedScanImageKey': passport.rectifiedScanImageKey,
      'marketValue': passport.marketValue,
      'savedAt': addedAt.toIso8601String(),
      'updatedAt': passport.updatedAt.toIso8601String(),
      'source': passport.isPassport ? 'scan' : 'search',
      'collectionType': collectionType,
      'centeringTop': topBottom?.$1,
      'centeringBottom': topBottom?.$2,
      'centeringLeft': leftRight?.$1,
      'centeringRight': leftRight?.$2,
      'tiltDegrees': tilt,
      'centeringTier': tier.grade,
      'centeringLabel': tier.displayLabel,
      'centeringDescription': tier.description,
      'notes': notes,
      'passport': passport.toJson(),
      'addedAt': addedAt.toIso8601String(),
    };
  }

  BinderCard copyWith({
    CardPassport? passport,
    DateTime? addedAt,
    String? localId,
    int? schemaVersion,
    String? collectionType,
    String? notes,
  }) {
    return BinderCard(
      passport: passport ?? this.passport,
      addedAt: addedAt ?? this.addedAt,
      localId: localId ?? this.localId,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      collectionType: collectionType ?? this.collectionType,
      notes: notes ?? this.notes,
    );
  }
}

class BinderCollection {
  BinderCollection({
    required this.id,
    required this.name,
    required this.cards,
    required this.createdAt,
    required this.updatedAt,
  });

  factory BinderCollection.wishlist() {
    final now = DateTime.now();
    return BinderCollection(
      id: BinderStore.wishlistCollectionId,
      name: 'Wishlist',
      cards: [],
      createdAt: now,
      updatedAt: now,
    );
  }

  factory BinderCollection.binder() {
    final now = DateTime.now();
    return BinderCollection(
      id: BinderStore.binderCollectionId,
      name: 'Binder',
      cards: [],
      createdAt: now,
      updatedAt: now,
    );
  }

  factory BinderCollection.gradingCandidate() {
    final now = DateTime.now();
    return BinderCollection(
      id: BinderStore.gradingCandidateCollectionId,
      name: 'Grading Candidate',
      cards: [],
      createdAt: now,
      updatedAt: now,
    );
  }

  factory BinderCollection.tradeSell() {
    final now = DateTime.now();
    return BinderCollection(
      id: BinderStore.tradeSellCollectionId,
      name: 'Trade/Sell',
      cards: [],
      createdAt: now,
      updatedAt: now,
    );
  }

  factory BinderCollection.fromJson(Map<String, dynamic> json) {
    return BinderCollection(
      id: json['id'] as String? ?? uniqueId('collection'),
      name: json['name'] as String? ?? 'Untitled Collection',
      cards: (json['cards'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(BinderCard.fromJson)
          .toList(),
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  final String id;
  final String name;
  final List<BinderCard> cards;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool containsPassport(CardPassport passport) {
    final key = passportIdentity(passport);
    return cards.any((card) => card.id == key);
  }

  BinderCollection copyWith({
    String? id,
    String? name,
    List<BinderCard>? cards,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return BinderCollection(
      id: id ?? this.id,
      name: name ?? this.name,
      cards: cards ?? this.cards,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'name': name,
      'cards': cards.map((card) => card.toJson()).toList(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }
}

class BinderStore extends ChangeNotifier {
  BinderStore({BinderRepository? repository})
    : _repository = repository ?? createBinderRepository();

  static const binderCollectionId = 'binder';
  static const wishlistCollectionId = 'wishlist';
  static const gradingCandidateCollectionId = 'grading_candidate';
  static const tradeSellCollectionId = 'trade_sell';
  static const _storageKey = 'sist.binder.collections.v1';

  final BinderRepository _repository;
  SharedPreferences? _preferences;
  bool _isLoaded = false;
  String? _saveError;
  List<BinderCollection> _collections = _defaultCollections();

  bool get isLoaded => _isLoaded;
  String? get saveError => _saveError;
  List<BinderCollection> get collections => List.unmodifiable(_collections);

  List<BinderCard> get allCards {
    final seen = <String>{};
    final cards = <BinderCard>[];
    for (final collection in _collections) {
      for (final card in collection.cards) {
        if (seen.add(card.id)) {
          cards.add(card);
        }
      }
    }
    return cards;
  }

  Future<void> load() async {
    _preferences = await SharedPreferences.getInstance();
    try {
      await _repository.initialize();
      final savedCollections = await _repository.loadCollections();
      if (savedCollections.isNotEmpty) {
        _collections = savedCollections
            .whereType<Map<String, dynamic>>()
            .map(BinderCollection.fromJson)
            .toList();
      } else {
        final migrated = _legacyCollections();
        _collections = migrated.isEmpty ? _defaultCollections() : migrated;
        await _save();
      }
    } catch (_) {
      final migrated = _legacyCollections();
      _collections = migrated.isEmpty ? _defaultCollections() : migrated;
    }
    _ensureDefaultCollections();
    await _hydrateSavedImages();
    _isLoaded = true;
    notifyListeners();
  }

  BinderCollection? collectionById(String id) {
    for (final collection in _collections) {
      if (collection.id == id) {
        return collection;
      }
    }
    return null;
  }

  Future<BinderCollection> createCollection(String name) async {
    final trimmed = name.trim();
    final now = DateTime.now();
    final collection = BinderCollection(
      id: uniqueId('collection'),
      name: trimmed.isEmpty ? 'Untitled Collection' : trimmed,
      cards: [],
      createdAt: now,
      updatedAt: now,
    );
    _collections = [..._collections, collection];
    await _save();
    notifyListeners();
    return collection;
  }

  Future<bool> addPassportToCollection({
    required String collectionId,
    required CardPassport passport,
  }) async {
    final index = _collections.indexWhere(
      (collection) => collection.id == collectionId,
    );
    if (index < 0 || _collections[index].containsPassport(passport)) {
      return false;
    }

    final now = DateTime.now();
    final collection = _collections[index];
    final collectionType = _collectionTypeForId(collection.id);
    final prepared = await _prepareSavedPassport(passport);
    final cards = [
      BinderCard(
        passport: prepared,
        addedAt: now,
        localId: passportIdentity(passport),
        collectionType: collectionType,
      ),
      ...collection.cards,
    ];
    _collections = [
      for (var i = 0; i < _collections.length; i++)
        if (i == index)
          collection.copyWith(cards: cards, updatedAt: now)
        else
          _collections[i],
    ];
    await _save();
    notifyListeners();
    return true;
  }

  Future<void> deleteCard(String localId) async {
    _collections = [
      for (final collection in _collections)
        collection.copyWith(
          cards: [
            for (final card in collection.cards)
              if (card.localId != localId) card,
          ],
          updatedAt: DateTime.now(),
        ),
    ];
    await _repository.deleteCard(localId);
    await _save();
    notifyListeners();
  }

  Future<void> moveCardToCollection({
    required String localId,
    required String collectionType,
  }) async {
    BinderCard? target;
    _collections = [
      for (final collection in _collections)
        collection.copyWith(
          cards: [
            for (final card in collection.cards)
              if (card.localId == localId)
                target = card.copyWith(collectionType: collectionType)
              else
                card,
          ].whereType<BinderCard>().toList(),
          updatedAt: DateTime.now(),
        ),
    ];
    final destinationId = _collectionIdForType(collectionType);
    final destinationIndex = _collections.indexWhere(
      (collection) => collection.id == destinationId,
    );
    if (target != null && destinationIndex >= 0) {
      final destination = _collections[destinationIndex];
      if (!destination.cards.any((card) => card.localId == localId)) {
        _collections[destinationIndex] = destination.copyWith(
          cards: [target, ...destination.cards],
          updatedAt: DateTime.now(),
        );
      }
    }
    await _repository.moveCardToCollection(localId, collectionType);
    await _save();
    notifyListeners();
  }

  Future<void> _save() async {
    _saveError = null;
    try {
      final data = _collections
          .map((collection) => collection.toJson())
          .toList();
      await _repository.saveCollections(data);
      await _preferences?.setString(_storageKey, jsonEncode(data));
    } catch (_) {
      _saveError =
          'Couldn’t save this card locally. Try freeing browser storage or saving fewer images.';
    }
  }

  List<BinderCollection> _legacyCollections() {
    final raw = _preferences?.getString(_storageKey);
    if (raw == null || raw.isEmpty) {
      return const [];
    }
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(BinderCollection.fromJson)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<CardPassport> _prepareSavedPassport(CardPassport passport) async {
    final scannedImage = passport.scannedImageBase64;
    if (scannedImage == null || scannedImage.isEmpty) {
      return passport;
    }
    try {
      final bytes = imageBytesFromBase64(scannedImage);
      final payload = BinderImagePayload(bytes: bytes, mimeType: 'image/jpeg');
      final imageKey =
          passport.localImageKey ?? await _repository.saveImageBlob(payload);
      final thumbnailKey =
          passport.localThumbnailKey ??
          await _repository.saveImageBlob(payload);
      return passport.copyWith(
        localImageKey: imageKey,
        localThumbnailKey: thumbnailKey,
        rectifiedScanImageKey: imageKey,
      );
    } catch (_) {
      return passport;
    }
  }

  Future<void> _hydrateSavedImages() async {
    final hydrated = <BinderCollection>[];
    for (final collection in _collections) {
      final cards = <BinderCard>[];
      for (final card in collection.cards) {
        cards.add(card.copyWith(passport: await _hydratePassportImage(card)));
      }
      hydrated.add(collection.copyWith(cards: cards));
    }
    _collections = hydrated;
  }

  Future<CardPassport> _hydratePassportImage(BinderCard card) async {
    final passport = card.passport;
    if (passport.scannedImageBase64 != null) {
      return passport;
    }
    final imageKey = passport.localThumbnailKey ?? passport.localImageKey;
    if (imageKey == null || imageKey.isEmpty) {
      return passport;
    }
    try {
      final payload = passport.localThumbnailKey == null
          ? await _repository.getCardImage(imageKey)
          : await _repository.getCardThumbnail(imageKey);
      if (payload == null) {
        return passport;
      }
      return passport.copyWith(
        scannedImageBase64: imageDataUriFromBytes(
          payload.bytes,
          mimeType: payload.mimeType,
        ),
      );
    } catch (_) {
      return passport;
    }
  }

  void _ensureDefaultCollections() {
    final defaults = _defaultCollections();
    final existing = _collections.map((collection) => collection.id).toSet();
    _collections = [
      for (final collection in defaults)
        if (!existing.contains(collection.id)) collection,
      ..._collections,
    ];
  }

  static List<BinderCollection> _defaultCollections() {
    return [
      BinderCollection.binder(),
      BinderCollection.wishlist(),
      BinderCollection.gradingCandidate(),
      BinderCollection.tradeSell(),
    ];
  }

  String _collectionTypeForId(String id) {
    return switch (id) {
      wishlistCollectionId => 'wishlist',
      gradingCandidateCollectionId => 'grading_candidate',
      tradeSellCollectionId => 'trade_sell',
      _ => 'binder',
    };
  }

  String _collectionIdForType(String type) {
    return switch (type) {
      'wishlist' => wishlistCollectionId,
      'grading_candidate' => gradingCandidateCollectionId,
      'trade_sell' => tradeSellCollectionId,
      _ => binderCollectionId,
    };
  }
}

class PokemonSet {
  const PokemonSet({
    required this.id,
    required this.name,
    required this.abbreviation,
    required this.publishedOn,
    required this.productCount,
  });

  factory PokemonSet.fromJson(Map<String, dynamic> json) {
    return PokemonSet(
      id: json['id'] as int,
      name: json['name'] as String? ?? 'Unknown Set',
      abbreviation: json['abbreviation'] as String? ?? '',
      publishedOn: DateTime.tryParse(json['published_on'] as String? ?? ''),
      productCount: json['product_count'] as int? ?? 0,
    );
  }

  final int id;
  final String name;
  final String abbreviation;
  final DateTime? publishedOn;
  final int productCount;
}

class PokemonProduct {
  const PokemonProduct({
    required this.id,
    required this.name,
    required this.cleanName,
    required this.number,
    required this.rarity,
    required this.imageUrl,
    required this.tcgplayerUrl,
    required this.set,
  });

  factory PokemonProduct.fromJson(Map<String, dynamic> json, PokemonSet set) {
    return PokemonProduct(
      id: json['id'] as int,
      name: json['name'] as String? ?? 'Unknown Card',
      cleanName: json['clean_name'] as String? ?? json['name'] as String? ?? '',
      number: json['number']?.toString(),
      rarity: json['rarity'] as String?,
      imageUrl: json['image_url'] as String?,
      tcgplayerUrl: json['tcgplayer_url'] as String?,
      set: set,
    );
  }

  final int id;
  final String name;
  final String cleanName;
  final String? number;
  final String? rarity;
  final String? imageUrl;
  final String? tcgplayerUrl;
  final PokemonSet set;
}

class PokemonPrice {
  const PokemonPrice({
    required this.subtype,
    required this.market,
    required this.low,
  });

  final String subtype;
  final double? market;
  final double? low;
}

class TcgTrackingApi {
  TcgTrackingApi({http.Client? client}) : _client = client ?? http.Client();

  static const _baseUrl = 'https://tcgtracking.com/tcgapi/v1';
  static const _pokemonCategory = 3;
  static const _requestTimeout = Duration(seconds: 10);
  final http.Client _client;
  List<PokemonSet>? _sets;
  final Map<int, List<PokemonProduct>> _productsBySet = {};
  final Map<int, Map<int, PokemonPrice?>> _pricesBySet = {};

  Future<List<CardPassport>> searchPokemon(String rawQuery) async {
    final query = rawQuery.trim();
    if (query.length < 2) {
      return const [];
    }

    final sets = await _getSets();
    final parsed = _ParsedQuery.parse(query, sets);
    final candidateSets = _candidateSets(parsed, sets);
    final matches = <PokemonProduct>[];

    matches.addAll(await _searchSets(candidateSets, parsed));

    if (matches.length < 18 && !parsed.hasSetHint) {
      final searchedIds = candidateSets.map((set) => set.id).toSet();
      final remainingSets = sets
          .where((set) => !searchedIds.contains(set.id))
          .toList();
      for (var start = 0; start < remainingSets.length; start += 8) {
        final batch = remainingSets.skip(start).take(8).toList();
        matches.addAll(await _searchSets(batch, parsed));
        if (parsed.number != null && matches.isNotEmpty) {
          break;
        }
        if (matches.length >= 18) {
          break;
        }
      }
    }

    matches.sort((a, b) => _score(parsed, b).compareTo(_score(parsed, a)));
    final topMatches = matches.take(18).toList();
    final setIds = topMatches.map((product) => product.set.id).toSet();
    final priceMaps = <int, Map<int, PokemonPrice?>>{};

    await Future.wait(
      setIds.map((setId) async {
        priceMaps[setId] = await _getPrices(setId);
      }),
    );

    return [
      for (final product in topMatches)
        _toPassport(product, priceMaps[product.set.id]?[product.id]),
    ];
  }

  Future<List<PokemonProduct>> _searchSets(
    List<PokemonSet> sets,
    _ParsedQuery parsed,
  ) async {
    final productLists = await Future.wait(sets.map(_getProducts));
    return [
      for (final products in productLists)
        ...products.where((product) => parsed.matchesProduct(product)),
    ];
  }

  Future<List<PokemonSet>> _getSets() async {
    final cached = _sets;
    if (cached != null) {
      return cached;
    }

    final json = await _getJson('$_baseUrl/$_pokemonCategory/sets');
    final sets =
        (json['sets'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map(PokemonSet.fromJson)
            .toList()
          ..sort((a, b) {
            final dateCompare = (b.publishedOn ?? DateTime(1900)).compareTo(
              a.publishedOn ?? DateTime(1900),
            );
            return dateCompare != 0 ? dateCompare : b.id.compareTo(a.id);
          });
    _sets = sets;
    return sets;
  }

  Future<List<PokemonProduct>> _getProducts(PokemonSet set) async {
    final cached = _productsBySet[set.id];
    if (cached != null) {
      return cached;
    }

    Map<String, dynamic>? json;
    try {
      json = await _getJsonOrNull(
        '$_baseUrl/$_pokemonCategory/sets/${set.id}/cards',
      );
    } catch (_) {
      // A single stale or throttled set must not fail the entire card search.
      return const [];
    }
    if (json == null) {
      return const [];
    }
    try {
      final products = (json['products'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map((product) => PokemonProduct.fromJson(product, set))
          .where(
            (product) => !product.name.toLowerCase().startsWith('code card'),
          )
          .toList();
      _productsBySet[set.id] = products;
      return products;
    } catch (_) {
      return const [];
    }
  }

  Future<Map<int, PokemonPrice?>> _getPrices(int setId) async {
    final cached = _pricesBySet[setId];
    if (cached != null) {
      return cached;
    }

    Map<String, dynamic>? json;
    try {
      json = await _getJsonOrNull(
        '$_baseUrl/$_pokemonCategory/sets/$setId/pricing',
      );
    } catch (_) {
      // Pricing is supplementary; card results should still be usable without it.
      return const {};
    }
    if (json == null) {
      return const {};
    }
    try {
      final rawPrices = (json['prices'] as Map<String, dynamic>? ?? {});
      final prices = <int, PokemonPrice?>{};
      for (final entry in rawPrices.entries) {
        prices[int.parse(entry.key)] = _bestPrice(entry.value);
      }
      _pricesBySet[setId] = prices;
      return prices;
    } catch (_) {
      return const {};
    }
  }

  Future<Map<String, dynamic>> _getJson(String url) async {
    final response = await _client.get(Uri.parse(url)).timeout(_requestTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('TCG Tracking request failed: ${response.statusCode}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>?> _getJsonOrNull(String url) async {
    final response = await _client.get(Uri.parse(url)).timeout(_requestTimeout);
    if (response.statusCode == 404) {
      return null;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('TCG Tracking request failed: ${response.statusCode}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  List<PokemonSet> _candidateSets(_ParsedQuery parsed, List<PokemonSet> sets) {
    if (parsed.setMatches.isNotEmpty) {
      return parsed.setMatches.take(8).toList();
    }

    final queryTokens = normalizeForSearch(parsed.cardQuery).split(' ');
    final nameSetMatches = sets.where((set) {
      final haystack = normalizeForSearch('${set.name} ${set.abbreviation}');
      return queryTokens.length > 1 &&
          queryTokens.any(
            (token) => token.length >= 4 && haystack.contains(token),
          );
    });

    final eraMatches = <PokemonSet>[];
    if (queryTokens.contains('vstar')) {
      eraMatches.addAll(
        sets.where((set) {
          final year = set.publishedOn?.year;
          return year != null && year >= 2021 && year <= 2023;
        }),
      );
    }

    return [
      ...nameSetMatches.take(4),
      ...eraMatches.take(36),
      ...sets.take(32),
    ].fold<List<PokemonSet>>([], (unique, set) {
      if (!unique.any((existing) => existing.id == set.id)) {
        unique.add(set);
      }
      return unique;
    });
  }

  int _score(_ParsedQuery parsed, PokemonProduct product) {
    final productName = normalizeForSearch(product.name);
    final cleanName = normalizeForSearch(product.cleanName);
    final cardQuery = normalizeForSearch(parsed.cardQuery);
    final queryTokens = cardQuery
        .split(' ')
        .where((token) => token.isNotEmpty)
        .toList();
    final productTokens = cleanName
        .split(' ')
        .where((token) => token.isNotEmpty)
        .toList();
    var score = 0;

    if (cleanName == cardQuery || productName == cardQuery) {
      score += 1000;
    } else if (cleanName.startsWith(cardQuery) ||
        productName.startsWith(cardQuery)) {
      score += 600;
    } else if (cleanName.contains(cardQuery) ||
        productName.contains(cardQuery)) {
      score += 350;
    }

    if (queryTokens.isNotEmpty &&
        queryTokens.every((token) => productTokens.contains(token))) {
      score += 300;
      score -= (productTokens.length - queryTokens.length).abs() * 8;
    }

    if (parsed.number != null &&
        productNumberMatches(product.number, parsed.number!)) {
      score += 500;
    }
    if (parsed.setMatches.any((set) => set.id == product.set.id)) {
      score += 400;
    }
    if (product.set.publishedOn != null) {
      score += product.set.publishedOn!.millisecondsSinceEpoch ~/ 100000000000;
    }
    return score;
  }

  PokemonPrice? _bestPrice(dynamic value) {
    final tcg = (value as Map<String, dynamic>)['tcg'] as Map<String, dynamic>?;
    if (tcg == null || tcg.isEmpty) {
      return null;
    }

    PokemonPrice? best;
    for (final entry in tcg.entries) {
      final data = entry.value as Map<String, dynamic>;
      final market = (data['market'] as num?)?.toDouble();
      final low = (data['low'] as num?)?.toDouble();
      final candidate = PokemonPrice(
        subtype: entry.key,
        market: market,
        low: low,
      );
      if ((candidate.market ?? candidate.low ?? -1) >
          (best?.market ?? best?.low ?? -1)) {
        best = candidate;
      }
    }
    return best;
  }

  CardPassport _toPassport(PokemonProduct product, PokemonPrice? price) {
    final estimate = price?.market == null
        ? 'Market unavailable'
        : '\$${price!.market!.toStringAsFixed(2)} market';
    final now = DateTime.now();

    return CardPassport(
      id: 'tcg-${product.id}',
      recordType: CardRecordType.lookup,
      externalApiId: product.id.toString(),
      productId: product.id,
      name: product.name,
      set: product.set.name,
      number: product.number ?? 'No number',
      year: product.set.publishedOn?.year.toString() ?? 'Unknown year',
      marketValue: estimate,
      condition: const CardCondition(grade: 'TBD', label: 'Needs scan'),
      centering: const CardCentering(
        topBottom: '--',
        leftRight: '--',
        tilt: '--',
      ),
      source: 'Live TCG Tracking',
      confidenceLabel: 'API result',
      tintValue: colorValueForSet(product.set.id),
      imageUrl: product.imageUrl,
      rarity: product.rarity,
      marketSubtype: price?.subtype,
      tcgplayerUrl: product.tcgplayerUrl,
      createdAt: now,
      updatedAt: now,
    );
  }
}

class _ParsedQuery {
  const _ParsedQuery({
    required this.cardQuery,
    required this.number,
    required this.setMatches,
  });

  final String cardQuery;
  final String? number;
  final List<PokemonSet> setMatches;

  bool get hasSetHint => setMatches.isNotEmpty;

  factory _ParsedQuery.parse(String query, List<PokemonSet> sets) {
    var working = query.trim();
    var numberMatch = RegExp(
      r'(?:#\s*)?\b([A-Za-z]{0,4}\d{1,4}[A-Za-z]?/\d{1,4})\b',
    ).firstMatch(working);
    numberMatch ??= RegExp(
      r'(?:#\s*)?\b([A-Za-z]{0,4}\d{1,4}[A-Za-z]?)\b',
    ).allMatches(working).lastOrNull;
    final number = numberMatch?.group(1);
    if (numberMatch != null) {
      working = working.replaceRange(numberMatch.start, numberMatch.end, ' ');
    }

    final normalized = normalizeForSearch(working);
    final setMatches = sets.where((set) {
      final abbr = normalizeForSearch(set.abbreviation);
      final name = normalizeForSearch(set.name);
      final isLikelySetName =
          name.contains(' ') ||
          name.length >= 8 ||
          normalized.startsWith('$name ');
      return (abbr.length >= 3 && normalized.split(' ').contains(abbr)) ||
          (name.length >= 4 && isLikelySetName && normalized.contains(name));
    }).toList();

    for (final set in setMatches.take(3)) {
      working = working
          .replaceAll(
            RegExp(RegExp.escape(set.abbreviation), caseSensitive: false),
            ' ',
          )
          .replaceAll(
            RegExp(RegExp.escape(set.name), caseSensitive: false),
            ' ',
          );
    }

    final cardQuery = working
        .replaceAll(RegExp(r'[#/:,-]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    return _ParsedQuery(
      cardQuery: cardQuery.isEmpty ? query : cardQuery,
      number: number,
      setMatches: setMatches,
    );
  }

  bool matchesProduct(PokemonProduct product) {
    final normalizedProduct = normalizeForSearch(
      '${product.name} ${product.cleanName}',
    );
    final tokens = normalizeForSearch(
      cardQuery,
    ).split(' ').where((token) => token.length >= 2).toList();
    final numberMatches =
        number == null || productNumberMatches(product.number, number!);
    if (!numberMatches) {
      return false;
    }
    if (tokens.isEmpty) {
      return numberMatches;
    }
    return tokens.every(normalizedProduct.contains);
  }
}

bool productNumberMatches(String? productNumber, String queryNumber) {
  if (productNumber == null) {
    return false;
  }
  final product = productNumber.toLowerCase().trim();
  final query = queryNumber.toLowerCase().trim();
  final productCompact = product.replaceAll(RegExp(r'[^a-z0-9]'), '');
  final queryCompact = query.replaceAll(RegExp(r'[^a-z0-9]'), '');
  if (product == query || productCompact == queryCompact) {
    return true;
  }

  if (query.contains('/')) {
    return collectorNumberPartsMatch(product, query);
  }

  final productPrefix = product.split('/').first;
  return productPrefix == query;
}

bool collectorNumberPartsMatch(String productNumber, String queryNumber) {
  final productParts = productNumber.split('/');
  final queryParts = queryNumber.split('/');
  if (productParts.length != 2 || queryParts.length != 2) {
    return false;
  }

  return normalizeCollectorPart(productParts.first) ==
          normalizeCollectorPart(queryParts.first) &&
      normalizeCollectorPart(productParts.last) ==
          normalizeCollectorPart(queryParts.last);
}

String normalizeCollectorPart(String value) {
  final cleaned = value.replaceAll(RegExp(r'[^a-z0-9]'), '');
  return cleaned.replaceFirst(RegExp(r'^0+(?=\d)'), '');
}

String normalizeForSearch(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String uniqueId(String prefix) {
  return '$prefix-${DateTime.now().microsecondsSinceEpoch}';
}

Color colorForSet(int setId) {
  return Color(colorValueForSet(setId));
}

int colorValueForSet(int setId) {
  const colors = [
    0xFF4B1DFF,
    0xFF0A84FF,
    0xFF30A46C,
    0xFFFF9F0A,
    0xFFFF375F,
    0xFF7D5FFF,
  ];
  return colors[setId.abs() % colors.length];
}

String passportIdentity(CardPassport passport) {
  if (passport.id.isNotEmpty) {
    return passport.id;
  }
  final productId = passport.productId;
  return productId == null
      ? normalizeForSearch(
          '${passport.recordType.storageValue}|${passport.name}|${passport.set}|${passport.number}',
        )
      : '${passport.recordType.storageValue}:product:$productId';
}

CardCandidate candidateFromPassport(CardPassport passport) {
  return CardCandidate(
    id: passport.externalApiId ?? passport.productId?.toString(),
    name: passport.name,
    setName: passport.set,
    cardNumber: passport.number,
    imageUrl: passport.imageUrl,
    marketValue: passport.marketValue,
    rarity: passport.rarity,
    raw: {
      'source': passport.source,
      'marketSubtype': passport.marketSubtype,
      'tcgplayerUrl': passport.tcgplayerUrl,
    },
  );
}

class HomeShell extends StatefulWidget {
  const HomeShell({this.samplePassportLoader, super.key});

  final SamplePassportLoader? samplePassportLoader;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final TextEditingController _searchController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();
  final TcgTrackingApi _api = TcgTrackingApi();
  final BackendScanClient _scanClient = BackendScanClient();
  final PassportDataService _passportService = const PassportDataService();
  final BinderStore _binderStore = BinderStore();
  final ValueNotifier<ScanProgressViewState> _scanProgress =
      ValueNotifier<ScanProgressViewState>(
        const ScanProgressViewState(
          title: 'Preparing scan',
          message: 'Waiting for image',
        ),
      );
  int _selectedIndex = 0;
  CardPassport? _latestScan;
  bool _scanProgressVisible = false;

  @override
  void initState() {
    super.initState();
    unawaited(_binderStore.load());
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scanProgress.dispose();
    _binderStore.dispose();
    super.dispose();
  }

  void _openPassport(CardPassport passport) {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (context) => PassportSheet(
        passport: passport,
        binderStore: _binderStore,
        scanClient: _scanClient,
        onScan: _pickScanImage,
      ),
    );
  }

  Future<void> _pickScanImage({CardPassport? sourceLookup}) async {
    final source = await _chooseImageSource();
    if (source == null || !mounted) {
      return;
    }

    final image = await _imagePicker.pickImage(
      source: source,
      maxWidth: 1600,
      imageQuality: 82,
    );
    if (image == null || !mounted) {
      return;
    }

    final bytes = await image.readAsBytes();
    if (!mounted) {
      return;
    }

    await _runScanPipeline(
      bytes: bytes,
      filename: image.name.isEmpty ? 'card-scan.jpg' : image.name,
      sourceLookup: sourceLookup,
    );
  }

  Future<ImageSource?> _chooseImageSource() async {
    return showCupertinoModalPopup<ImageSource>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('Scan card'),
        message: const Text('Take a photo or upload an image.'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(context).pop(ImageSource.camera),
            child: const Text('Take Photo'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(context).pop(ImageSource.gallery),
            child: const Text('Upload Image'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  Future<void> _runScanPipeline({
    required Uint8List bytes,
    required String filename,
    CardPassport? sourceLookup,
  }) async {
    _showScanProgress();
    try {
      if (sourceLookup == null) {
        await _runUnknownCardScan(bytes: bytes, filename: filename);
      } else {
        await _runKnownCardScan(
          bytes: bytes,
          filename: filename,
          sourceLookup: sourceLookup,
        );
      }
    } on ScanApiException catch (error) {
      _showScanError(error.message);
    } catch (error) {
      _showScanError('Scan failed. ${error.toString()}');
    }
  }

  Future<void> _runUnknownCardScan({
    required Uint8List bytes,
    required String filename,
  }) async {
    _setScanProgress(
      'Uploading scan',
      'Sending the image to the scan pipeline.',
    );
    final scan = await _scanClient.scanImageQueued(
      bytes: bytes,
      filename: filename,
      onStatus: (status) {
        if (status == 'running') {
          _setScanProgress(
            'Segmenting card',
            'Finding, rectifying, and identifying the card.',
          );
        }
      },
    );

    var rectifiedImage = scan.rectifiedImageBase64;
    if (scan.status == 'segmentation_failed' ||
        (scan.segmentation?.manualBoundaryRequired ?? false)) {
      rectifiedImage = await _rectifyFromManualBoundary(
        bytes: bytes,
        segmentation: scan.segmentation,
      );
      if (rectifiedImage == null) {
        return;
      }
    }

    if (rectifiedImage == null) {
      throw const ScanApiException('The backend did not return a card image.');
    }

    if (scan.isAccepted &&
        !(scan.segmentation?.manualBoundaryRequired ?? false) &&
        scan.detectedCard != null) {
      _finishPassport(
        _passportService.createPassportFromBackend(
          candidate: scan.detectedCard,
          rectifiedImageBase64: rectifiedImage,
          centering: scan.centering,
        ),
      );
      return;
    }

    final passport = await _identifyOrConfirmCard(rectifiedImage);
    if (passport != null) {
      _finishPassport(passport);
    }
  }

  Future<void> _runKnownCardScan({
    required Uint8List bytes,
    required String filename,
    required CardPassport sourceLookup,
  }) async {
    _setScanProgress(
      'Segmenting card',
      'Finding the card boundary before generating the passport.',
    );
    final segmentation = await _scanClient.segmentImage(
      bytes: bytes,
      filename: filename,
    );

    var rectifiedImage = segmentation.rectifiedImageBase64;
    if (segmentation.status == 'segmentation_failed' ||
        segmentation.manualBoundaryRequired) {
      rectifiedImage = await _rectifyFromManualBoundary(
        bytes: bytes,
        segmentation: segmentation,
        sourceLookup: sourceLookup,
      );
      if (rectifiedImage == null) {
        return;
      }
    }

    if (rectifiedImage == null) {
      throw const ScanApiException('The backend did not return a card image.');
    }

    _setScanProgress(
      'Analyzing passport',
      'Checking centering against the selected card.',
    );
    final centering = await _scanClient.analyzeCentering(
      rectifiedImageBase64: rectifiedImage,
      match: candidateFromPassport(sourceLookup),
    );
    _finishPassport(
      _passportService.createPassportFromBackend(
        sourceLookup: sourceLookup,
        rectifiedImageBase64: rectifiedImage,
        centering: centering,
      ),
    );
  }

  Future<void> _openSamplePassport() async {
    if (widget.samplePassportLoader != null) {
      final passport = await widget.samplePassportLoader!();
      if (mounted) {
        _openPassport(passport);
      }
      return;
    }

    _showScanProgress();
    try {
      _setScanProgress(
        'Loading sample scan',
        'Preparing the Pikachu ex sample image.',
      );
      final data = await rootBundle.load(samplePikachuAssetPath);
      final bytes = data.buffer.asUint8List();
      final sourceLookup = CardPassport.samplePikachuLookup();

      _setScanProgress(
        'Rectifying sample',
        'Sending the tested boundary to the backend.',
      );
      final rectified = await _scanClient.rectifyImage(
        originalImageBase64: imageDataUriFromBytes(bytes),
        boundary: samplePikachuBoundary(),
      );

      _setScanProgress(
        'Running XFeat',
        'Checking centering against the known card.',
      );
      final centering = await _scanClient.analyzeCentering(
        rectifiedImageBase64: rectified.base64,
        match: candidateFromPassport(sourceLookup),
      );

      _finishPassport(
        _passportService.createPassportFromBackend(
          sourceLookup: sourceLookup,
          rectifiedImageBase64: rectified.base64,
          centering: centering,
        ),
      );
    } on ScanApiException catch (error) {
      _showScanError(error.message);
    } catch (error) {
      _showScanError('Sample scan failed. ${error.toString()}');
    }
  }

  Future<String?> _rectifyFromManualBoundary({
    required Uint8List bytes,
    SegmentationResult? segmentation,
    CardPassport? sourceLookup,
  }) async {
    _hideScanProgress();
    final outcome = await showCupertinoModalPopup<BoundaryCorrectionOutcome>(
      context: context,
      builder: (context) => BoundaryCorrectionSheet(
        imageBytes: bytes,
        initialBoundary: segmentation?.boundary,
        reason: segmentation?.manualBoundaryReason,
      ),
    );

    if (!mounted || outcome == null) {
      return null;
    }
    if (outcome.retryScan) {
      await _pickScanImage(sourceLookup: sourceLookup);
      return null;
    }

    _showScanProgress();
    _setScanProgress('Rectifying card', 'Normalizing the corrected boundary.');
    final rectified = await _scanClient.rectifyImage(
      originalImageBase64: imageDataUriFromBytes(bytes),
      boundary: outcome.boundary!,
    );
    return rectified.base64;
  }

  Future<CardPassport?> _identifyOrConfirmCard(String rectifiedImage) async {
    _setScanProgress('Identifying card', 'Matching the normalized card image.');
    final identification = await _scanClient.identifyCard(rectifiedImage);
    if (identification.isAccepted && identification.bestMatch != null) {
      return _passportService.createPassportFromBackend(
        candidate: identification.bestMatch,
        rectifiedImageBase64: rectifiedImage,
        centering: identification.centering,
      );
    }

    _hideScanProgress();
    if (!mounted) {
      return null;
    }
    final selected = await showCupertinoModalPopup<CardPassport>(
      context: context,
      builder: (context) => ManualCardLookupSheet(
        api: _api,
        suggestedCandidates: identification.candidates,
      ),
    );
    if (!mounted || selected == null) {
      return null;
    }

    _showScanProgress();
    _setScanProgress('Generating passport', 'Using your confirmed card match.');
    final centering = await _scanClient.analyzeCentering(
      rectifiedImageBase64: rectifiedImage,
      match: candidateFromPassport(selected),
    );
    return _passportService.createPassportFromBackend(
      sourceLookup: selected,
      rectifiedImageBase64: rectifiedImage,
      centering: centering,
    );
  }

  void _finishPassport(CardPassport passport) {
    _hideScanProgress();
    setState(() => _latestScan = passport);
    _openPassport(passport);
  }

  void _showScanProgress() {
    if (_scanProgressVisible || !mounted) {
      return;
    }
    _scanProgressVisible = true;
    showCupertinoModalPopup<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ScanProgressSheet(progress: _scanProgress),
    ).whenComplete(() {
      _scanProgressVisible = false;
    });
  }

  void _hideScanProgress() {
    if (_scanProgressVisible && mounted) {
      Navigator.of(context).pop();
      _scanProgressVisible = false;
    }
  }

  void _setScanProgress(String title, String message) {
    _scanProgress.value = ScanProgressViewState(title: title, message: message);
  }

  void _showScanError(String message) {
    _scanProgress.value = ScanProgressViewState(
      title: 'Scan needs attention',
      message: message,
      isError: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomePage(
        api: _api,
        searchController: _searchController,
        latestScan: _latestScan,
        onScan: _pickScanImage,
        onSamplePassport: _openSamplePassport,
        onOpenPassport: _openPassport,
      ),
      BinderPage(binderStore: _binderStore, onOpenPassport: _openPassport),
    ];

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: pages[_selectedIndex],
          ),
        ),
      ),
      bottomNavigationBar: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: CupertinoTabBar(
            currentIndex: _selectedIndex,
            activeColor: const Color(0xFF4B1DFF),
            inactiveColor: const Color(0xFF7D7A91),
            backgroundColor: CupertinoColors.systemBackground.withValues(
              alpha: 0.94,
            ),
            border: const Border(top: BorderSide(color: Color(0xFFE5E5EA))),
            height: 64,
            onTap: (index) {
              setState(() => _selectedIndex = index);
            },
            items: const [
              BottomNavigationBarItem(
                icon: Icon(CupertinoIcons.house),
                activeIcon: Icon(CupertinoIcons.house_fill),
                label: 'Home',
              ),
              BottomNavigationBarItem(
                icon: Icon(CupertinoIcons.collections),
                activeIcon: Icon(CupertinoIcons.collections_solid),
                label: 'Binder',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ScanProgressViewState {
  const ScanProgressViewState({
    required this.title,
    required this.message,
    this.isError = false,
  });

  final String title;
  final String message;
  final bool isError;
}

class ScanProgressSheet extends StatelessWidget {
  const ScanProgressSheet({required this.progress, super.key});

  final ValueNotifier<ScanProgressViewState> progress;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 28),
        decoration: const BoxDecoration(
          color: Color(0xFFFBFAFF),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          child: ValueListenableBuilder<ScanProgressViewState>(
            valueListenable: progress,
            builder: (context, state, _) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 42,
                    height: 5,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD7D2E7),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Icon(
                    state.isError
                        ? CupertinoIcons.exclamationmark_triangle_fill
                        : CupertinoIcons.camera_viewfinder,
                    color: state.isError
                        ? const Color(0xFFFF375F)
                        : const Color(0xFF4B1DFF),
                    size: 42,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    state.title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: const Color(0xFF11123E),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    state.message,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF72718E),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 22),
                  if (state.isError)
                    CupertinoButton(
                      color: const Color(0xFF4B1DFF),
                      borderRadius: BorderRadius.circular(16),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text(
                        'Close',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    )
                  else
                    const CupertinoActivityIndicator(radius: 14),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class BoundaryCorrectionOutcome {
  const BoundaryCorrectionOutcome.confirmed(this.boundary) : retryScan = false;
  const BoundaryCorrectionOutcome.retry() : boundary = null, retryScan = true;

  final CardBoundary? boundary;
  final bool retryScan;
}

class BoundaryCorrectionSheet extends StatefulWidget {
  const BoundaryCorrectionSheet({
    required this.imageBytes,
    required this.initialBoundary,
    required this.reason,
    super.key,
  });

  final Uint8List imageBytes;
  final CardBoundary? initialBoundary;
  final String? reason;

  @override
  State<BoundaryCorrectionSheet> createState() =>
      _BoundaryCorrectionSheetState();
}

class _BoundaryCorrectionSheetState extends State<BoundaryCorrectionSheet> {
  ui.Image? _image;
  CardBoundary? _boundary;
  CardBoundary? _autoBoundary;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    final image = await decodeUiImage(widget.imageBytes);
    if (!mounted) {
      return;
    }
    final boundary =
        widget.initialBoundary ??
        CardBoundary.defaultForImage(
          imageWidth: image.width,
          imageHeight: image.height,
        );
    setState(() {
      _image = image;
      _boundary = boundary;
      _autoBoundary = boundary;
    });
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    final boundary = _boundary;
    return Align(
      alignment: Alignment.bottomCenter,
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.92,
        width: double.infinity,
        child: Container(
          decoration: const BoxDecoration(
            color: Color(0xFFFBFAFF),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 42,
                  height: 5,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD7D2E7),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 18, 22, 10),
                  child: Column(
                    children: [
                      Text(
                        'Adjust boundary',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              color: const Color(0xFF11123E),
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        boundaryReasonCopy(widget.reason),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF72718E),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: DecoratedBox(
                        decoration: const BoxDecoration(color: Colors.black),
                        child: image == null || boundary == null
                            ? const Center(
                                child: CupertinoActivityIndicator(radius: 14),
                              )
                            : BoundaryEditor(
                                image: image,
                                boundary: boundary,
                                onChanged: (next) {
                                  setState(() => _boundary = next);
                                },
                              ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      CupertinoButton(
                        minimumSize: const Size(0, 42),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        color: const Color(0xFF4B1DFF),
                        borderRadius: BorderRadius.circular(14),
                        onPressed: boundary == null
                            ? null
                            : () => Navigator.of(context).pop(
                                BoundaryCorrectionOutcome.confirmed(boundary),
                              ),
                        child: const Text(
                          'Confirm boundary',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                      CupertinoButton(
                        minimumSize: const Size(0, 42),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        borderRadius: BorderRadius.circular(14),
                        color: const Color(0xFFF4F1FF),
                        onPressed: _autoBoundary == null
                            ? null
                            : () => setState(() => _boundary = _autoBoundary),
                        child: const Text('Use auto'),
                      ),
                      CupertinoButton(
                        minimumSize: const Size(0, 42),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        borderRadius: BorderRadius.circular(14),
                        color: const Color(0xFFF4F1FF),
                        onPressed: image == null
                            ? null
                            : () => setState(
                                () => _boundary = CardBoundary.defaultForImage(
                                  imageWidth: image.width,
                                  imageHeight: image.height,
                                ),
                              ),
                        child: const Text('Reset points'),
                      ),
                      CupertinoButton(
                        minimumSize: const Size(0, 42),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        borderRadius: BorderRadius.circular(14),
                        onPressed: () => Navigator.of(
                          context,
                        ).pop(const BoundaryCorrectionOutcome.retry()),
                        child: const Text('Retry scan'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class BoundaryEditor extends StatefulWidget {
  const BoundaryEditor({
    required this.image,
    required this.boundary,
    required this.onChanged,
    super.key,
  });

  final ui.Image image;
  final CardBoundary boundary;
  final ValueChanged<CardBoundary> onChanged;

  @override
  State<BoundaryEditor> createState() => _BoundaryEditorState();
}

class _BoundaryEditorState extends State<BoundaryEditor> {
  BoundaryHandle? _dragging;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final imageRect = fittedImageRect(widget.image, size);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (details) {
            setState(() {
              _dragging = nearestHandle(
                details.localPosition,
                imageRect,
                widget.image,
                widget.boundary,
              );
            });
          },
          onPanUpdate: (details) {
            final handle = _dragging;
            if (handle == null) {
              return;
            }
            final point = canvasToImagePoint(
              details.localPosition,
              imageRect,
              widget.image,
            );
            widget.onChanged(widget.boundary.copyWithPoint(handle, point));
          },
          onPanEnd: (_) => setState(() => _dragging = null),
          onPanCancel: () => setState(() => _dragging = null),
          child: CustomPaint(
            painter: BoundaryEditorPainter(
              image: widget.image,
              boundary: widget.boundary,
              dragging: _dragging,
            ),
            size: Size.infinite,
          ),
        );
      },
    );
  }
}

class BoundaryEditorPainter extends CustomPainter {
  const BoundaryEditorPainter({
    required this.image,
    required this.boundary,
    required this.dragging,
  });

  final ui.Image image;
  final CardBoundary boundary;
  final BoundaryHandle? dragging;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = fittedImageRect(image, size);
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      rect,
      Paint()..filterQuality = FilterQuality.medium,
    );

    final path = Path()
      ..moveToPoint(imageToCanvasPoint(boundary.topLeft, rect, image))
      ..lineToPoint(imageToCanvasPoint(boundary.topRight, rect, image))
      ..cubicToPoint(
        imageToCanvasPoint(boundary.rightCurve1, rect, image),
        imageToCanvasPoint(boundary.rightCurve2, rect, image),
        imageToCanvasPoint(boundary.bottomRight, rect, image),
      )
      ..lineToPoint(imageToCanvasPoint(boundary.bottomLeft, rect, image))
      ..cubicToPoint(
        imageToCanvasPoint(boundary.leftCurve2, rect, image),
        imageToCanvasPoint(boundary.leftCurve1, rect, image),
        imageToCanvasPoint(boundary.topLeft, rect, image),
      )
      ..close();

    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF4B1DFF).withValues(alpha: 0.14)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF4B1DFF)
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke,
    );

    for (final handle in BoundaryHandle.values) {
      final point = imageToCanvasPoint(boundary.pointFor(handle), rect, image);
      final active = handle == dragging;
      canvas.drawCircle(
        point,
        active ? 12 : 9,
        Paint()
          ..color = active ? const Color(0xFF4B1DFF) : Colors.white
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        point,
        active ? 12 : 9,
        Paint()
          ..color = const Color(0xFF4B1DFF)
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke,
      );
    }

    final activeHandle = dragging;
    if (activeHandle != null) {
      _drawMagnifier(canvas, size, rect, activeHandle);
    }
  }

  void _drawMagnifier(
    Canvas canvas,
    Size size,
    Rect imageRect,
    BoundaryHandle activeHandle,
  ) {
    final imagePoint = boundary.pointFor(activeHandle);
    final center = imageToCanvasPoint(imagePoint, imageRect, image);
    final previewSize = math.min(138.0, size.shortestSide * 0.42);
    final dst = Rect.fromCenter(
      center: Offset(
        center.dx < size.width / 2
            ? size.width - previewSize / 2 - 14
            : 14 + previewSize / 2,
        math.max(14 + previewSize / 2, center.dy - previewSize * 0.85),
      ),
      width: previewSize,
      height: previewSize,
    );
    final srcSize = 96.0;
    final src =
        Rect.fromCenter(
          center: Offset(imagePoint.x, imagePoint.y),
          width: srcSize,
          height: srcSize,
        ).intersect(
          Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        );
    final clip = Path()..addOval(dst);

    canvas.save();
    canvas.clipPath(clip);
    canvas.drawImageRect(
      image,
      src,
      dst,
      Paint()..filterQuality = FilterQuality.high,
    );
    canvas.restore();
    canvas.drawOval(
      dst,
      Paint()
        ..color = Colors.white
        ..strokeWidth = 4
        ..style = PaintingStyle.stroke,
    );
    canvas.drawOval(
      dst,
      Paint()
        ..color = const Color(0xFF4B1DFF)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );
    canvas.drawLine(
      Offset(dst.center.dx - 9, dst.center.dy),
      Offset(dst.center.dx + 9, dst.center.dy),
      Paint()
        ..color = const Color(0xFF4B1DFF)
        ..strokeWidth = 2,
    );
    canvas.drawLine(
      Offset(dst.center.dx, dst.center.dy - 9),
      Offset(dst.center.dx, dst.center.dy + 9),
      Paint()
        ..color = const Color(0xFF4B1DFF)
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant BoundaryEditorPainter oldDelegate) {
    return oldDelegate.image != image ||
        oldDelegate.boundary != boundary ||
        oldDelegate.dragging != dragging;
  }
}

class ManualCardLookupSheet extends StatefulWidget {
  const ManualCardLookupSheet({
    required this.api,
    required this.suggestedCandidates,
    super.key,
  });

  final TcgTrackingApi api;
  final List<CardCandidate> suggestedCandidates;

  @override
  State<ManualCardLookupSheet> createState() => _ManualCardLookupSheetState();
}

class _ManualCardLookupSheetState extends State<ManualCardLookupSheet> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  bool _isSearching = false;
  List<CardPassport> _results = const [];
  CardPassport? _selected;

  @override
  void initState() {
    super.initState();
    _results = widget.suggestedCandidates
        .map(passportFromCandidate)
        .whereType<CardPassport>()
        .toList();
  }

  @override
  void dispose() {
    _controller.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (query.length < 2) {
      setState(() {
        _isSearching = false;
        _results = widget.suggestedCandidates
            .map(passportFromCandidate)
            .whereType<CardPassport>()
            .toList();
      });
      return;
    }
    setState(() => _isSearching = true);
    _debounce = Timer(const Duration(milliseconds: 280), () async {
      try {
        final results = await widget.api.searchPokemon(query);
        if (mounted) {
          setState(() {
            _results = results;
            _isSearching = false;
          });
        }
      } catch (_) {
        if (mounted) {
          setState(() => _isSearching = false);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.82,
        width: double.infinity,
        child: Container(
          decoration: const BoxDecoration(
            color: Color(0xFFFBFAFF),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 18),
                    children: [
                      Center(
                        child: Container(
                          width: 42,
                          height: 5,
                          decoration: BoxDecoration(
                            color: const Color(0xFFD7D2E7),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      Text(
                        'Confirm card',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              color: const Color(0xFF11123E),
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Search and pick the exact card before generating the passport.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF72718E),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 18),
                      CupertinoSearchTextField(
                        controller: _controller,
                        placeholder: 'Search card name or number',
                        onChanged: _onChanged,
                      ),
                      const SizedBox(height: 16),
                      if (_isSearching)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 22),
                          child: Center(
                            child: CupertinoActivityIndicator(radius: 12),
                          ),
                        ),
                      for (final result in _results) ...[
                        DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: _selected?.id == result.id
                                  ? const Color(0xFF4B1DFF)
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: PassportListTile(
                            passport: result,
                            onTap: () => setState(() => _selected = result),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
                  decoration: const BoxDecoration(
                    color: Color(0xFFFBFAFF),
                    border: Border(top: BorderSide(color: Color(0xFFE5E5EA))),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: CupertinoButton(
                          color: const Color(0xFFF4F1FF),
                          borderRadius: BorderRadius.circular(16),
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text(
                            'Retry scan',
                            style: TextStyle(color: Color(0xFF4B1DFF)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: CupertinoButton(
                          color: const Color(0xFF4B1DFF),
                          borderRadius: BorderRadius.circular(16),
                          onPressed: _selected == null
                              ? null
                              : () => Navigator.of(context).pop(_selected),
                          child: const Text(
                            'Confirm',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<ui.Image> decodeUiImage(Uint8List bytes) {
  final completer = Completer<ui.Image>();
  ui.decodeImageFromList(bytes, completer.complete);
  return completer.future;
}

String boundaryReasonCopy(String? reason) {
  return switch (reason) {
    'low_segmentation_confidence' =>
      'The detected edge needs a quick check before we make a passport.',
    'card_too_small_in_frame' =>
      'The card is small in the photo. Pull the points onto the card edges.',
    'segmentation_confidence_unavailable' =>
      'We found a likely card area, but need you to confirm the boundary.',
    _ =>
      'Drag the points onto the card edges. A magnifier appears while dragging.',
  };
}

CardPassport? passportFromCandidate(CardCandidate candidate) {
  final now = DateTime.now();
  final name = candidate.name;
  if (name == null || name.isEmpty) {
    return null;
  }
  return CardPassport(
    id: candidate.id == null ? uniqueId('lookup') : 'tcg-${candidate.id}',
    recordType: CardRecordType.lookup,
    externalApiId: candidate.id,
    productId: int.tryParse(candidate.id ?? ''),
    name: name,
    set: candidate.setName ?? 'Unknown Set',
    number: candidate.cardNumber ?? 'No number',
    year: 'Unknown year',
    marketValue: candidate.marketValue ?? 'Market unavailable',
    imageUrl: candidate.imageUrl,
    rarity: candidate.rarity,
    source: 'Scan candidate',
    confidenceLabel: candidate.confidence == null
        ? null
        : '${candidate.confidence!.toStringAsFixed(0)}% match',
    condition: const CardCondition(grade: 'TBD', label: 'Needs scan'),
    centering: const CardCentering(
      topBottom: '--',
      leftRight: '--',
      tilt: '--',
    ),
    createdAt: now,
    updatedAt: now,
  );
}

Rect fittedImageRect(ui.Image image, Size size) {
  final fitted = applyBoxFit(
    BoxFit.contain,
    Size(image.width.toDouble(), image.height.toDouble()),
    size,
  );
  return Alignment.center.inscribe(fitted.destination, Offset.zero & size);
}

Offset imageToCanvasPoint(BoundaryPoint point, Rect rect, ui.Image image) {
  return Offset(
    rect.left + (point.x / image.width) * rect.width,
    rect.top + (point.y / image.height) * rect.height,
  );
}

BoundaryPoint canvasToImagePoint(Offset point, Rect rect, ui.Image image) {
  final x = ((point.dx - rect.left) / rect.width * image.width).clamp(
    0.0,
    image.width.toDouble(),
  );
  final y = ((point.dy - rect.top) / rect.height * image.height).clamp(
    0.0,
    image.height.toDouble(),
  );
  return BoundaryPoint(x: x, y: y);
}

BoundaryHandle? nearestHandle(
  Offset point,
  Rect rect,
  ui.Image image,
  CardBoundary boundary,
) {
  BoundaryHandle? nearest;
  var nearestDistance = double.infinity;
  for (final handle in BoundaryHandle.values) {
    final handlePoint = imageToCanvasPoint(
      boundary.pointFor(handle),
      rect,
      image,
    );
    final distance = (point - handlePoint).distance;
    if (distance < nearestDistance) {
      nearestDistance = distance;
      nearest = handle;
    }
  }
  return nearestDistance <= 42 ? nearest : null;
}

extension PathPointExtensions on Path {
  void moveToPoint(Offset point) => moveTo(point.dx, point.dy);
  void lineToPoint(Offset point) => lineTo(point.dx, point.dy);
  void cubicToPoint(Offset control1, Offset control2, Offset end) {
    cubicTo(control1.dx, control1.dy, control2.dx, control2.dy, end.dx, end.dy);
  }
}

class HomePage extends StatefulWidget {
  const HomePage({
    required this.api,
    required this.searchController,
    required this.latestScan,
    required this.onScan,
    required this.onSamplePassport,
    required this.onOpenPassport,
    super.key,
  });

  final TcgTrackingApi api;
  final TextEditingController searchController;
  final CardPassport? latestScan;
  final ScanLauncher onScan;
  final Future<void> Function() onSamplePassport;
  final ValueChanged<CardPassport> onOpenPassport;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String _query = '';
  List<CardPassport> _results = const [];
  Timer? _debounce;
  bool _isSearching = false;
  String? _searchError;
  int _searchRun = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    setState(() {
      _query = value;
      _searchError = null;
    });

    _debounce?.cancel();
    final trimmed = value.trim();
    if (trimmed.length < 2) {
      setState(() {
        _results = const [];
        _isSearching = false;
      });
      return;
    }

    setState(() => _isSearching = true);
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _runSearch(trimmed);
    });
  }

  Future<void> _runSearch(String query) async {
    final run = ++_searchRun;
    try {
      final results = await widget.api.searchPokemon(query);
      if (!mounted || run != _searchRun) {
        return;
      }
      setState(() {
        _results = results;
        _isSearching = false;
      });
    } catch (_) {
      if (!mounted || run != _searchRun) {
        return;
      }
      setState(() {
        _results = const [];
        _isSearching = false;
        _searchError = 'Could not reach TCG Tracking. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final showResults = _query.trim().isNotEmpty;

    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxHeight < 720;
          final veryCompact = constraints.maxHeight < 640;
          final horizontalPadding = compact ? 20.0 : 24.0;
          final topPadding = compact ? 18.0 : 28.0;
          final titleGap = compact ? 18.0 : 28.0;
          final afterSearchGap = compact ? 12.0 : 20.0;
          final heroHeight = veryCompact ? 236.0 : (compact ? 268.0 : 322.0);
          final scanTitleSize = veryCompact ? 36.0 : (compact ? 40.0 : 42.0);
          final sampleGap = compact ? 18.0 : 28.0;

          return CustomScrollView(
            key: const ValueKey('home-page'),
            physics: const ClampingScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  topPadding,
                  horizontalPadding,
                  24,
                ),
                sliver: SliverList.list(
                  children: [
                    Text(
                      'Should I Slab This',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            fontSize: compact ? 25 : 28,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF11123E),
                          ),
                    ),
                    SizedBox(height: titleGap),
                    CupertinoSearchTextField(
                      controller: widget.searchController,
                      placeholder: 'Search card, set, or number',
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 15,
                      ),
                      prefixInsets: const EdgeInsetsDirectional.fromSTEB(
                        14,
                        0,
                        8,
                        0,
                      ),
                      suffixInsets: const EdgeInsetsDirectional.fromSTEB(
                        8,
                        0,
                        12,
                        0,
                      ),
                      itemColor: const Color(0xFF66658A),
                      style: const TextStyle(
                        color: Color(0xFF11123E),
                        fontSize: 17,
                        fontWeight: FontWeight.w500,
                      ),
                      placeholderStyle: const TextStyle(
                        color: Color(0xFF77748A),
                        fontSize: 17,
                        fontWeight: FontWeight.w400,
                      ),
                      decoration: BoxDecoration(
                        color: CupertinoColors.systemBackground,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFE5E5EA)),
                      ),
                      onChanged: _onSearchChanged,
                    ),
                    SizedBox(height: afterSearchGap),
                    if (showResults)
                      SearchResults(
                        results: _results,
                        isLoading: _isSearching,
                        error: _searchError,
                        onOpenPassport: widget.onOpenPassport,
                      )
                    else ...[
                      ScanHero(height: heroHeight, onScan: widget.onScan),
                      SizedBox(height: compact ? 12 : 20),
                      Text(
                        'Tap to scan',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.displaySmall
                            ?.copyWith(
                              color: const Color(0xFF4B1DFF),
                              fontSize: scanTitleSize,
                              fontWeight: FontWeight.w900,
                              height: 1,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.latestScan == null
                            ? 'Scan a card. Get its passport.'
                            : 'Latest scan: ${widget.latestScan!.name}',
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontSize: compact ? 15 : 16,
                              color: const Color(0xFF72718E),
                              fontWeight: FontWeight.w500,
                            ),
                      ),
                      SizedBox(height: sampleGap),
                      SamplePassportCard(
                        compact: compact,
                        passport: dummyPassports.first,
                        onTap: widget.onSamplePassport,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class ScanHero extends StatelessWidget {
  const ScanHero({required this.height, required this.onScan, super.key});

  final double height;
  final ScanLauncher onScan;

  @override
  Widget build(BuildContext context) {
    final circleSize = height * 0.57;
    final iconSize = circleSize * 0.42;

    return RepaintBoundary(
      child: SizedBox(
        height: height,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: CustomPaint(painter: ScanHaloPainter(scale: height / 322)),
            ),
            Semantics(
              button: true,
              label: 'Scan card',
              child: CupertinoButton(
                minimumSize: Size.zero,
                padding: EdgeInsets.zero,
                borderRadius: BorderRadius.circular(circleSize / 2),
                onPressed: () => onScan(),
                child: Container(
                  width: circleSize,
                  height: circleSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFFD777F7),
                        Color(0xFF4D27F4),
                        Color(0xFF3A28D8),
                      ],
                    ),
                    border: Border.all(color: Colors.white, width: 5),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF6A3CFF).withValues(alpha: 0.22),
                        blurRadius: 24,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Icon(
                    CupertinoIcons.camera_fill,
                    color: Colors.white,
                    size: iconSize,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ScanHaloPainter extends CustomPainter {
  const ScanHaloPainter({required this.scale});

  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = const Color(0xFFE7DFFF);
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFCBB9FF).withValues(alpha: 0.26),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: 150 * scale));

    canvas.drawCircle(center, 150 * scale, glowPaint);
    canvas.drawCircle(center, 144 * scale, ringPaint);
    canvas.drawCircle(
      center,
      108 * scale,
      ringPaint..color = const Color(0xFFF0EAFF),
    );

    final dotPaint = Paint()
      ..color = const Color(0xFFDCD5F6).withValues(alpha: 0.8)
      ..style = PaintingStyle.fill;
    for (var side = -1; side <= 1; side += 2) {
      for (var row = 0; row < 7; row++) {
        for (var column = 0; column < 5; column++) {
          canvas.drawCircle(
            Offset(
              center.dx + side * ((120 + column * 9) * scale),
              center.dy + (-30 + row * 9) * scale,
            ),
            1.15 * scale,
            dotPaint,
          );
        }
      }
    }

    _drawSpark(
      canvas,
      Offset(center.dx - 112 * scale, center.dy - 96 * scale),
      12 * scale,
    );
    _drawSpark(
      canvas,
      Offset(center.dx + 126 * scale, center.dy - 126 * scale),
      11 * scale,
    );
    _drawSpark(
      canvas,
      Offset(center.dx + 150 * scale, center.dy + 70 * scale),
      11 * scale,
    );
    _drawSpark(
      canvas,
      Offset(center.dx - 126 * scale, center.dy + 108 * scale),
      9 * scale,
    );
  }

  void _drawSpark(Canvas canvas, Offset center, double radius) {
    final path = Path()
      ..moveTo(center.dx, center.dy - radius)
      ..quadraticBezierTo(
        center.dx + 3,
        center.dy - 3,
        center.dx + radius,
        center.dy,
      )
      ..quadraticBezierTo(
        center.dx + 3,
        center.dy + 3,
        center.dx,
        center.dy + radius,
      )
      ..quadraticBezierTo(
        center.dx - 3,
        center.dy + 3,
        center.dx - radius,
        center.dy,
      )
      ..quadraticBezierTo(
        center.dx - 3,
        center.dy - 3,
        center.dx,
        center.dy - radius,
      );

    canvas.drawPath(
      path,
      Paint()..color = const Color(0xFFC7B8FF).withValues(alpha: 0.86),
    );
  }

  @override
  bool shouldRepaint(covariant ScanHaloPainter oldDelegate) {
    return oldDelegate.scale != scale;
  }
}

class SamplePassportCard extends StatelessWidget {
  const SamplePassportCard({
    this.compact = false,
    required this.passport,
    required this.onTap,
    super.key,
  });

  final bool compact;
  final CardPassport passport;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      minimumSize: Size.zero,
      padding: EdgeInsets.zero,
      onPressed: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: CupertinoColors.systemBackground,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE5E5EA)),
        ),
        child: Padding(
          padding: EdgeInsets.all(compact ? 14 : 16),
          child: Row(
            children: [
              Container(
                width: compact ? 62 : 70,
                height: compact ? 62 : 70,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF9F0),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  CupertinoIcons.sparkles,
                  color: const Color(0xFF22A45D),
                  size: compact ? 28 : 32,
                ),
              ),
              SizedBox(width: compact ? 14 : 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'See a Sample Passport',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: compact ? 20 : 21,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF11123E),
                        height: 1.1,
                      ),
                    ),
                    SizedBox(height: compact ? 5 : 7),
                    Text(
                      'Try it in seconds',
                      style: TextStyle(
                        fontSize: compact ? 15 : 16,
                        color: const Color(0xFF72718E),
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                CupertinoIcons.chevron_forward,
                color: Color(0xFF4B1DFF),
                size: 24,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SearchResults extends StatelessWidget {
  const SearchResults({
    required this.results,
    required this.isLoading,
    required this.error,
    required this.onOpenPassport,
    super.key,
  });

  final List<CardPassport> results;
  final bool isLoading;
  final String? error;
  final ValueChanged<CardPassport> onOpenPassport;

  @override
  Widget build(BuildContext context) {
    if (isLoading && results.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 72),
        child: Center(child: CupertinoActivityIndicator(radius: 15)),
      );
    }

    if (error != null) {
      return SearchMessage(
        icon: CupertinoIcons.exclamationmark_triangle,
        title: error!,
      );
    }

    if (results.isEmpty) {
      return const SearchMessage(
        icon: CupertinoIcons.doc_text_search,
        title: 'No Pokemon cards found',
      );
    }

    return Column(
      children: [
        if (isLoading) ...[
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: CupertinoActivityIndicator(radius: 10),
          ),
        ],
        for (final passport in results) ...[
          PassportListTile(
            passport: passport,
            onTap: () => onOpenPassport(passport),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class SearchMessage extends StatelessWidget {
  const SearchMessage({required this.icon, required this.title, super.key});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 80),
      child: Column(
        children: [
          Icon(icon, size: 52, color: const Color(0xFF9996B7)),
          const SizedBox(height: 18),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: const Color(0xFF11123E),
            ),
          ),
        ],
      ),
    );
  }
}

class BinderPage extends StatelessWidget {
  const BinderPage({
    required this.binderStore,
    required this.onOpenPassport,
    super.key,
  });

  final BinderStore binderStore;
  final ValueChanged<CardPassport> onOpenPassport;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: binderStore,
      builder: (context, _) {
        final collections = binderStore.collections;
        final allCards = binderStore.allCards;

        return SafeArea(
          child: CustomScrollView(
            key: const ValueKey('binder-page'),
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 18),
                sliver: SliverList.list(
                  children: [
                    Text(
                      'Binder',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF11123E),
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      allCards.isEmpty
                          ? 'Collections for cards and passports'
                          : '${allCards.length} saved card${allCards.length == 1 ? '' : 's'}',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: const Color(0xFF72718E),
                      ),
                    ),
                    const SizedBox(height: 26),
                    Text(
                      'Collections',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: const Color(0xFF11123E),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 12),
                    BinderCollectionsRow(
                      collections: collections,
                      onOpenCollection: (collection) {
                        showCupertinoModalPopup<void>(
                          context: context,
                          builder: (context) => BinderCollectionSheet(
                            collection: collection,
                            onOpenPassport: onOpenPassport,
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 26),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'All Cards',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  color: const Color(0xFF11123E),
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                        ),
                        Text(
                          '${allCards.length}',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: const Color(0xFF72718E),
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (allCards.isEmpty)
                      const BinderEmptyState()
                    else
                      BinderGallery(
                        cards: allCards,
                        onOpenPassport: onOpenPassport,
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class BinderCollectionsRow extends StatelessWidget {
  const BinderCollectionsRow({
    required this.collections,
    required this.onOpenCollection,
    super.key,
  });

  final List<BinderCollection> collections;
  final ValueChanged<BinderCollection> onOpenCollection;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 152,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemBuilder: (context, index) {
          final collection = collections[index];
          return BinderCollectionCard(
            collection: collection,
            onTap: () => onOpenCollection(collection),
          );
        },
        separatorBuilder: (context, index) => const SizedBox(width: 12),
        itemCount: collections.length,
      ),
    );
  }
}

class BinderCollectionCard extends StatelessWidget {
  const BinderCollectionCard({
    required this.collection,
    required this.onTap,
    super.key,
  });

  final BinderCollection collection;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final preview = collection.cards.take(3).toList();
    return SizedBox(
      width: 178,
      child: CupertinoButton(
        minimumSize: Size.zero,
        padding: EdgeInsets.zero,
        onPressed: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: CupertinoColors.systemBackground,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE5E5EA)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 62,
                  child: Stack(
                    children: [
                      if (preview.isEmpty)
                        Container(
                          width: 62,
                          height: 62,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF4F1FF),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(
                            CupertinoIcons.collections,
                            color: Color(0xFF4B1DFF),
                          ),
                        )
                      else
                        for (var i = 0; i < preview.length; i++)
                          Positioned(
                            left: i * 34,
                            child: CardThumbnail(
                              passport: preview[i].passport,
                              size: 62,
                              portrait: true,
                            ),
                          ),
                    ],
                  ),
                ),
                const Spacer(),
                Text(
                  collection.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF11123E),
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${collection.cards.length} card${collection.cards.length == 1 ? '' : 's'}',
                  style: const TextStyle(
                    color: Color(0xFF72718E),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class BinderEmptyState extends StatelessWidget {
  const BinderEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: CupertinoColors.systemBackground,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE5E5EA)),
      ),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: const Color(0xFFF4F1FF),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              CupertinoIcons.collections,
              color: Color(0xFF4B1DFF),
              size: 34,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No saved cards yet',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: const Color(0xFF11123E),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Open a card or passport and add it to Binder.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF72718E),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class BinderGallery extends StatelessWidget {
  const BinderGallery({
    required this.cards,
    required this.onOpenPassport,
    super.key,
  });

  final List<BinderCard> cards;
  final ValueChanged<CardPassport> onOpenPassport;

  @override
  Widget build(BuildContext context) {
    final left = <BinderCard>[];
    final right = <BinderCard>[];
    for (var index = 0; index < cards.length; index++) {
      (index.isEven ? left : right).add(cards[index]);
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            children: [
              for (final card in left) ...[
                BinderGalleryCard(
                  passport: card.passport,
                  onTap: () => onOpenPassport(card.passport),
                ),
                const SizedBox(height: 14),
              ],
            ],
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            children: [
              for (final card in right) ...[
                BinderGalleryCard(
                  passport: card.passport,
                  onTap: () => onOpenPassport(card.passport),
                ),
                const SizedBox(height: 14),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class BinderGalleryCard extends StatelessWidget {
  const BinderGalleryCard({
    required this.passport,
    required this.onTap,
    super.key,
  });

  final CardPassport passport;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      minimumSize: Size.zero,
      padding: EdgeInsets.zero,
      onPressed: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: CupertinoColors.systemBackground,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE5E5EA)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: CardThumbnail(
                  passport: passport,
                  size: 176,
                  portrait: true,
                ),
              ),
              const SizedBox(height: 10),
              RecordTypePill(recordType: passport.recordType),
              const SizedBox(height: 8),
              Text(
                passport.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF11123E),
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                '${passport.set} · ${passport.number}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF72718E),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                passport.estimate,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF188A4C),
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class RecordTypePill extends StatelessWidget {
  const RecordTypePill({required this.recordType, super.key});

  final CardRecordType recordType;

  @override
  Widget build(BuildContext context) {
    final isPassport = recordType == CardRecordType.passport;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: isPassport ? const Color(0xFFEAF9F0) : const Color(0xFFF4F1FF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        recordType.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: isPassport ? const Color(0xFF2B8A43) : const Color(0xFF4B1DFF),
          fontSize: 11,
          fontWeight: FontWeight.w900,
          decoration: TextDecoration.none,
        ),
      ),
    );
  }
}

class BinderCollectionSheet extends StatelessWidget {
  const BinderCollectionSheet({
    required this.collection,
    required this.onOpenPassport,
    super.key,
  });

  final BinderCollection collection;
  final ValueChanged<CardPassport> onOpenPassport;

  @override
  Widget build(BuildContext context) {
    final cards = collection.cards;
    return Align(
      alignment: Alignment.bottomCenter,
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.82,
        width: double.infinity,
        child: Container(
          decoration: const BoxDecoration(
            color: Color(0xFFFBFAFF),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SafeArea(
            top: false,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 5,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD7D2E7),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  collection.name,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: const Color(0xFF11123E),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${cards.length} card${cards.length == 1 ? '' : 's'}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: const Color(0xFF72718E),
                  ),
                ),
                const SizedBox(height: 24),
                if (cards.isEmpty)
                  const BinderEmptyState()
                else
                  BinderGallery(
                    cards: cards,
                    onOpenPassport: (passport) {
                      Navigator.of(context).pop();
                      onOpenPassport(passport);
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PassportListTile extends StatelessWidget {
  const PassportListTile({
    required this.passport,
    required this.onTap,
    super.key,
  });

  final CardPassport passport;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      minimumSize: Size.zero,
      padding: EdgeInsets.zero,
      onPressed: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: CupertinoColors.systemBackground,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE5E5EA)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CardThumbnail(passport: passport, size: 70, portrait: true),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      passport.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF11123E),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${passport.set} · ${passport.number}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF72718E),
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      passport.estimate,
                      style: const TextStyle(
                        fontSize: 16,
                        color: Color(0xFF188A4C),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                CupertinoIcons.chevron_forward,
                color: Color(0xFF9A97AA),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CardThumbnail extends StatelessWidget {
  const CardThumbnail({
    required this.passport,
    this.size = 88,
    this.portrait = false,
    super.key,
  });

  final CardPassport passport;
  final double size;
  final bool portrait;

  @override
  Widget build(BuildContext context) {
    final width = portrait ? size * 0.72 : size;
    final height = size;

    if (passport.scannedImageBase64 != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.12),
        child: ColoredBox(
          color: CupertinoColors.systemBackground,
          child: Image.memory(
            imageBytesFromBase64(passport.scannedImageBase64!),
            width: width,
            height: height,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.low,
            errorBuilder: (context, error, stackTrace) {
              return CardThumbnailFallback(passport: passport, size: size);
            },
          ),
        ),
      );
    }

    if (passport.imageUrl != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.12),
        child: ColoredBox(
          color: CupertinoColors.systemBackground,
          child: Image.network(
            passport.imageUrl!,
            width: width,
            height: height,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.low,
            errorBuilder: (context, error, stackTrace) {
              return CardThumbnailFallback(passport: passport, size: size);
            },
          ),
        ),
      );
    }

    return CardThumbnailFallback(passport: passport, size: size);
  }
}

class CardThumbnailFallback extends StatelessWidget {
  const CardThumbnailFallback({
    required this.passport,
    required this.size,
    super.key,
  });

  final CardPassport passport;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            passport.tint.withValues(alpha: 0.86),
            const Color(0xFF15164A),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: passport.tint.withValues(alpha: 0.22),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Center(
        child: Icon(
          CupertinoIcons.rectangle_stack_fill,
          color: Colors.white,
          size: size * 0.48,
        ),
      ),
    );
  }
}

class PassportSheet extends StatefulWidget {
  const PassportSheet({
    required this.passport,
    required this.binderStore,
    required this.scanClient,
    required this.onScan,
    super.key,
  });

  final CardPassport passport;
  final BinderStore binderStore;
  final BackendScanClient scanClient;
  final ScanLauncher onScan;

  @override
  State<PassportSheet> createState() => _PassportSheetState();
}

class _PassportSheetState extends State<PassportSheet> {
  Timer? _messageTimer;
  String? _message;

  @override
  void dispose() {
    _messageTimer?.cancel();
    super.dispose();
  }

  Future<void> _sharePassport() async {
    final scannedImage = widget.passport.scannedImageBase64;
    if (scannedImage != null) {
      _showMessage('Generating share card');
      try {
        final result = await widget.scanClient.renderPassport(
          rectifiedImageBase64: scannedImage,
          cardName: widget.passport.name,
          setName: widget.passport.set,
          cardNumber: widget.passport.number,
          marketValue: widget.passport.marketValue,
          topBottom: widget.passport.centering.topBottom,
          leftRight: widget.passport.centering.leftRight,
          tilt: widget.passport.centering.tilt,
          rank: widget.passport.condition.grade,
        );
        if (!mounted) {
          return;
        }
        final shareResult = await SharePlus.instance.share(
          ShareParams(
            title: 'Should I Slab This passport',
            text: 'Made with shouldislabthis.com',
            files: [
              XFile.fromData(
                imageBytesFromBase64(result.imageBase64),
                name: 'should-i-slab-this-passport.png',
                mimeType: 'image/png',
              ),
            ],
            fileNameOverrides: const ['should-i-slab-this-passport.png'],
            downloadFallbackEnabled: false,
          ),
        );
        if (!mounted) {
          return;
        }
        if (shareResult.status == ShareResultStatus.unavailable) {
          _showMessage('Browser sharing is not available here');
        } else if (shareResult.status == ShareResultStatus.dismissed) {
          _showMessage('Share cancelled');
        } else {
          _showMessage('Share sheet opened');
        }
      } catch (error) {
        if (mounted) {
          _showMessage('Could not open browser share');
        }
      }
      return;
    }

    await Clipboard.setData(
      ClipboardData(
        text:
            '${widget.passport.name} · ${widget.passport.set} ${widget.passport.number} · ${widget.passport.marketValue}',
      ),
    );
    _showMessage('Passport copied');
  }

  Future<void> _addToBinder() async {
    final saved = await showCupertinoModalPopup<bool>(
      context: context,
      builder: (context) => AddToBinderSheet(
        passport: widget.passport,
        binderStore: widget.binderStore,
      ),
    );
    if (saved == true && mounted) {
      _showMessage('Added to Binder');
    }
  }

  Future<void> _scanLookup() async {
    final onScan = widget.onScan;
    Navigator.of(context).pop();
    await onScan(sourceLookup: widget.passport);
  }

  void _showMessage(String message) {
    _messageTimer?.cancel();
    setState(() => _message = message);
    _messageTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) {
        setState(() => _message = null);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final sheetHeight = MediaQuery.sizeOf(context).height * 0.92;
    final passport = widget.passport;

    return Align(
      alignment: Alignment.bottomCenter,
      child: SizedBox(
        height: sheetHeight,
        width: double.infinity,
        child: Container(
          decoration: const BoxDecoration(
            color: Color(0xFFFBFAFF),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                bottom: 94,
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(28),
                  ),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                    children: [
                      Center(
                        child: Container(
                          width: 42,
                          height: 5,
                          decoration: BoxDecoration(
                            color: const Color(0xFFD7D2E7),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      PassportLargeImage(passport: passport),
                      const SizedBox(height: 18),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  passport.name,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(
                                        color: const Color(0xFF11123E),
                                        fontSize: 27,
                                        fontWeight: FontWeight.w900,
                                        height: 1.05,
                                      ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  'Market Value',
                                  style: Theme.of(context).textTheme.labelLarge
                                      ?.copyWith(
                                        color: const Color(0xFF72718E),
                                        fontWeight: FontWeight.w800,
                                      ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  passport.marketValue,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(
                                        color: const Color(0xFF4B1DFF),
                                        fontWeight: FontWeight.w900,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          if (passport.isPassport) ...[
                            const SizedBox(width: 14),
                            CenteringTierBadge(centering: passport.centering),
                          ],
                        ],
                      ),
                      const SizedBox(height: 24),
                      PassportInfoPanel(passport: passport),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: PassportActionBar(
                  recordType: passport.recordType,
                  onShare: _sharePassport,
                  onScan: _scanLookup,
                  onAddToBinder: _addToBinder,
                ),
              ),
              if (_message != null)
                Positioned(
                  left: 24,
                  right: 24,
                  bottom: 100,
                  child: PassportToast(message: _message!),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class SharePreviewSheet extends StatelessWidget {
  const SharePreviewSheet({required this.imageBase64, super.key});

  final String imageBase64;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.82,
        width: double.infinity,
        child: Container(
          decoration: const BoxDecoration(
            color: Color(0xFFFBFAFF),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 42,
                  height: 5,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD7D2E7),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Share passport',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: const Color(0xFF11123E),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Image.memory(
                        imageBytesFromBase64(imageBase64),
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
                  child: CupertinoButton(
                    color: const Color(0xFF4B1DFF),
                    borderRadius: BorderRadius.circular(16),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text(
                      'Done',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PassportLargeImage extends StatelessWidget {
  const PassportLargeImage({required this.passport, super.key});

  final CardPassport passport;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: AspectRatio(
          aspectRatio: 0.72,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: passport.scannedImageBase64 != null
                ? Image.memory(
                    imageBytesFromBase64(passport.scannedImageBase64!),
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.medium,
                    errorBuilder: (context, error, stackTrace) {
                      return PassportPlaceholderArt(passport: passport);
                    },
                  )
                : passport.imageUrl == null
                ? PassportPlaceholderArt(passport: passport)
                : Image.network(
                    passport.imageUrl!,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.medium,
                    errorBuilder: (context, error, stackTrace) {
                      return PassportPlaceholderArt(passport: passport);
                    },
                  ),
          ),
        ),
      ),
    );
  }
}

Uint8List imageBytesFromBase64(String value) {
  final commaIndex = value.indexOf(',');
  final payload = commaIndex >= 0 ? value.substring(commaIndex + 1) : value;
  return base64Decode(payload);
}

String imageDataUriFromBytes(
  Uint8List bytes, {
  String mimeType = 'image/jpeg',
}) {
  return 'data:$mimeType;base64,${base64Encode(bytes)}';
}

class PassportPlaceholderArt extends StatelessWidget {
  const PassportPlaceholderArt({required this.passport, super.key});

  final CardPassport passport;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF171044), Color(0xFF4B1DFF), Color(0xFF1B68D8)],
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.74),
          width: 3,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4B1DFF).withValues(alpha: 0.22),
            blurRadius: 28,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            top: 24,
            left: 18,
            right: 18,
            child: Text(
              passport.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w900,
                height: 1.05,
                decoration: TextDecoration.none,
              ),
            ),
          ),
          Positioned(
            top: 112,
            left: 42,
            child: Icon(
              CupertinoIcons.moon_stars_fill,
              color: Colors.white.withValues(alpha: 0.9),
              size: 78,
            ),
          ),
          Positioned(
            right: -34,
            bottom: 88,
            child: Icon(
              CupertinoIcons.sparkles,
              color: Colors.white.withValues(alpha: 0.22),
              size: 210,
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 24,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${passport.set} · ${passport.number}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
                const Icon(CupertinoIcons.star_fill, color: Colors.white),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class CenteringTierBadge extends StatelessWidget {
  const CenteringTierBadge({required this.centering, super.key});

  final CardCentering centering;

  @override
  Widget build(BuildContext context) {
    final tier = centering.tier;
    return Container(
      width: 98,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F1FF),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Text(
            tier.grade,
            style: const TextStyle(
              color: Color(0xFF4B1DFF),
              fontSize: 23,
              fontWeight: FontWeight.w900,
              decoration: TextDecoration.none,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            tier.label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF4B1DFF),
              fontSize: 12,
              fontWeight: FontWeight.w800,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }
}

class PassportInfoPanel extends StatelessWidget {
  const PassportInfoPanel({required this.passport, super.key});

  final CardPassport passport;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: CupertinoColors.systemBackground,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE5E5EA)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: PassportInfoTile(
                  icon: CupertinoIcons.layers_alt_fill,
                  label: 'Set',
                  value: passport.set,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: PassportInfoTile(
                  icon: CupertinoIcons.number,
                  label: 'Number',
                  value: passport.number,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: PassportInfoTile(
                  icon: CupertinoIcons.star_fill,
                  label: 'Rarity',
                  value: passport.rarity ?? 'Unknown',
                ),
              ),
            ],
          ),
          if (passport.isPassport) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Divider(height: 1, color: Color(0xFFE5E5EA)),
            ),
            CenteringBlock(centering: passport.centering),
          ] else if (passport.hasLookupMetadata) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Divider(height: 1, color: Color(0xFFE5E5EA)),
            ),
            LookupMetadataRows(passport: passport),
          ],
        ],
      ),
    );
  }
}

class LookupMetadataRows extends StatelessWidget {
  const LookupMetadataRows({required this.passport, super.key});

  final CardPassport passport;

  @override
  Widget build(BuildContext context) {
    final rows = [
      if (passport.source != null) ('Source', passport.source!),
      if (passport.marketSubtype != null)
        ('Price type', passport.marketSubtype!),
      if (passport.productId != null)
        ('Product ID', passport.productId!.toString()),
    ];

    return Column(
      children: [
        for (var index = 0; index < rows.length; index++) ...[
          LookupMetadataRow(label: rows[index].$1, value: rows[index].$2),
          if (index != rows.length - 1) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class LookupMetadataRow extends StatelessWidget {
  const LookupMetadataRow({
    required this.label,
    required this.value,
    super.key,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF72718E),
              fontSize: 14,
              fontWeight: FontWeight.w700,
              decoration: TextDecoration.none,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Flexible(
          flex: 2,
          child: Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: Color(0xFF11123E),
              fontSize: 14,
              fontWeight: FontWeight.w900,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ],
    );
  }
}

class PassportInfoTile extends StatelessWidget {
  const PassportInfoTile({
    required this.icon,
    required this.label,
    required this.value,
    super.key,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: const Color(0xFF4B1DFF), size: 24),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF72718E),
            fontSize: 13,
            fontWeight: FontWeight.w700,
            decoration: TextDecoration.none,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFF11123E),
            fontSize: 14,
            fontWeight: FontWeight.w900,
            decoration: TextDecoration.none,
          ),
        ),
      ],
    );
  }
}

class CenteringBlock extends StatelessWidget {
  const CenteringBlock({required this.centering, super.key});

  final CardCentering centering;

  @override
  Widget build(BuildContext context) {
    final tier = centering.tier;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              CupertinoIcons.scope,
              color: Color(0xFF4B1DFF),
              size: 24,
            ),
            const SizedBox(width: 7),
            const Expanded(
              child: Text(
                'Centering',
                style: TextStyle(
                  color: Color(0xFF72718E),
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
            Text(
              tier.displayLabel,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Color(0xFF4B1DFF),
                fontSize: 14,
                fontWeight: FontWeight.w900,
                decoration: TextDecoration.none,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            CenteringPill(label: 'T/B', value: centering.topBottom),
            CenteringPill(label: 'L/R', value: centering.leftRight),
            CenteringPill(label: 'Tilt', value: centering.tilt),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          tier.description,
          style: const TextStyle(
            color: Color(0xFF11123E),
            fontSize: 14,
            fontWeight: FontWeight.w700,
            height: 1.25,
            decoration: TextDecoration.none,
          ),
        ),
        if (tier.tiltAffected) ...[
          const SizedBox(height: 8),
          const Text(
            'Tilt affected this centering tier.',
            style: TextStyle(
              color: Color(0xFF72718E),
              fontSize: 12,
              fontWeight: FontWeight.w700,
              height: 1.2,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ],
    );
  }
}

class CenteringPill extends StatelessWidget {
  const CenteringPill({required this.label, required this.value, super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 84,
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F1FF),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF72718E),
              fontSize: 12,
              fontWeight: FontWeight.w800,
              decoration: TextDecoration.none,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF11123E),
              fontSize: 14,
              fontWeight: FontWeight.w900,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }
}

class PassportActionBar extends StatelessWidget {
  const PassportActionBar({
    required this.recordType,
    required this.onShare,
    required this.onScan,
    required this.onAddToBinder,
    super.key,
  });

  final CardRecordType recordType;
  final Future<void> Function() onShare;
  final Future<void> Function() onScan;
  final Future<void> Function() onAddToBinder;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
        decoration: const BoxDecoration(
          color: Color(0xFFFBFAFF),
          border: Border(top: BorderSide(color: Color(0xFFE5E5EA))),
        ),
        child: Row(
          children: [
            Expanded(
              child: PassportActionButton(
                label: recordType == CardRecordType.passport ? 'Share' : 'Scan',
                icon: recordType == CardRecordType.passport
                    ? CupertinoIcons.share
                    : CupertinoIcons.camera_fill,
                onPressed: recordType == CardRecordType.passport
                    ? onShare
                    : onScan,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: PassportActionButton(
                label: 'Add to Binder',
                icon: CupertinoIcons.rectangle_stack_badge_plus,
                onPressed: onAddToBinder,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PassportActionButton extends StatelessWidget {
  const PassportActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    super.key,
  });

  final String label;
  final IconData icon;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: CupertinoButton(
        minimumSize: Size.zero,
        padding: EdgeInsets.zero,
        borderRadius: BorderRadius.circular(18),
        pressedOpacity: 0.76,
        onPressed: onPressed,
        child: Container(
          height: 58,
          width: double.infinity,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFF4B1DFF),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF4B1DFF).withValues(alpha: 0.22),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 22),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    height: 1,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AddToBinderSheet extends StatefulWidget {
  const AddToBinderSheet({
    required this.passport,
    required this.binderStore,
    super.key,
  });

  final CardPassport passport;
  final BinderStore binderStore;

  @override
  State<AddToBinderSheet> createState() => _AddToBinderSheetState();
}

class _AddToBinderSheetState extends State<AddToBinderSheet> {
  final TextEditingController _controller = TextEditingController();
  bool _isSaving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _saveToCollection(BinderCollection collection) async {
    if (collection.containsPassport(widget.passport)) {
      Navigator.of(context).pop(false);
      return;
    }
    setState(() => _isSaving = true);
    await widget.binderStore.addPassportToCollection(
      collectionId: collection.id,
      passport: widget.passport,
    );
    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _createAndSave() async {
    final name = _controller.text.trim();
    if (name.isEmpty) {
      return;
    }
    setState(() => _isSaving = true);
    final collection = await widget.binderStore.createCollection(name);
    await widget.binderStore.addPassportToCollection(
      collectionId: collection.id,
      passport: widget.passport,
    );
    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.72,
        width: double.infinity,
        child: Container(
          decoration: const BoxDecoration(
            color: Color(0xFFFBFAFF),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SafeArea(
            top: false,
            child: AnimatedBuilder(
              animation: widget.binderStore,
              builder: (context, _) {
                return ListView(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
                  children: [
                    Center(
                      child: Container(
                        width: 42,
                        height: 5,
                        decoration: BoxDecoration(
                          color: const Color(0xFFD7D2E7),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      'Add to Binder',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            color: const Color(0xFF11123E),
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.passport.name,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: const Color(0xFF72718E),
                      ),
                    ),
                    const SizedBox(height: 22),
                    for (final collection
                        in widget.binderStore.collections) ...[
                      AddToCollectionTile(
                        collection: collection,
                        isSaved: collection.containsPassport(widget.passport),
                        onTap: _isSaving
                            ? null
                            : () => _saveToCollection(collection),
                      ),
                      const SizedBox(height: 10),
                    ],
                    const SizedBox(height: 14),
                    Text(
                      'New collection',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: const Color(0xFF11123E),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: CupertinoTextField(
                            controller: _controller,
                            placeholder: 'Collection name',
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 14,
                            ),
                            decoration: BoxDecoration(
                              color: CupertinoColors.systemBackground,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: const Color(0xFFE5E5EA),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        CupertinoButton(
                          minimumSize: const Size(0, 48),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          color: const Color(0xFF4B1DFF),
                          borderRadius: BorderRadius.circular(16),
                          onPressed: _isSaving ? null : _createAndSave,
                          child: const Icon(
                            CupertinoIcons.plus,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class AddToCollectionTile extends StatelessWidget {
  const AddToCollectionTile({
    required this.collection,
    required this.isSaved,
    required this.onTap,
    super.key,
  });

  final BinderCollection collection;
  final bool isSaved;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      minimumSize: Size.zero,
      padding: EdgeInsets.zero,
      onPressed: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: CupertinoColors.systemBackground,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE5E5EA)),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: const Color(0xFFF4F1FF),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                CupertinoIcons.collections,
                color: Color(0xFF4B1DFF),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    collection.name,
                    style: const TextStyle(
                      color: Color(0xFF11123E),
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${collection.cards.length} card${collection.cards.length == 1 ? '' : 's'}',
                    style: const TextStyle(
                      color: Color(0xFF72718E),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              isSaved
                  ? CupertinoIcons.checkmark_circle_fill
                  : CupertinoIcons.add,
              color: const Color(0xFF4B1DFF),
            ),
          ],
        ),
      ),
    );
  }
}

class PassportToast extends StatelessWidget {
  const PassportToast({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF11123E).withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Text(
            message,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ),
    );
  }
}

class MetricPill extends StatelessWidget {
  const MetricPill({
    required this.label,
    required this.value,
    required this.icon,
    super.key,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F1FF),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF4B1DFF), size: 22),
          const SizedBox(height: 10),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: const Color(0xFF72718E),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: const Color(0xFF11123E),
              fontWeight: FontWeight.w900,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

class InfoRow extends StatelessWidget {
  const InfoRow({required this.label, required this.value, super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          SizedBox(
            width: 86,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF72718E),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF11123E),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
