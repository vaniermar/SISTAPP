import 'scan_config.dart';

class BoundaryPoint {
  const BoundaryPoint({required this.x, required this.y});

  factory BoundaryPoint.fromJson(Map<String, dynamic> json) {
    return BoundaryPoint(
      x: (json['x'] as num?)?.toDouble() ?? 0,
      y: (json['y'] as num?)?.toDouble() ?? 0,
    );
  }

  final double x;
  final double y;

  BoundaryPoint lerp(BoundaryPoint other, double t) {
    return BoundaryPoint(x: x + (other.x - x) * t, y: y + (other.y - y) * t);
  }

  Map<String, Object?> toJson() {
    return {'x': x, 'y': y};
  }
}

enum BoundaryHandle {
  topLeft('top_left', 'TL'),
  topRight('top_right', 'TR'),
  bottomRight('bottom_right', 'BR'),
  bottomLeft('bottom_left', 'BL'),
  leftCurve1('left_curve_1', 'L1'),
  leftCurve2('left_curve_2', 'L2'),
  rightCurve1('right_curve_1', 'R1'),
  rightCurve2('right_curve_2', 'R2');

  const BoundaryHandle(this.jsonKey, this.label);

  final String jsonKey;
  final String label;
}

class CardBoundary {
  const CardBoundary({
    required this.topLeft,
    required this.topRight,
    required this.bottomRight,
    required this.bottomLeft,
    required this.leftCurve1,
    required this.leftCurve2,
    required this.rightCurve1,
    required this.rightCurve2,
    required this.originalImageWidth,
    required this.originalImageHeight,
    this.segmentationConfidence,
    this.cardAreaRatio,
    this.autoDetected = true,
    this.manuallyCorrected = false,
  });

  factory CardBoundary.defaultForImage({
    required int imageWidth,
    required int imageHeight,
  }) {
    final marginX = imageWidth * 0.08;
    final marginY = imageHeight * 0.08;
    final tl = BoundaryPoint(x: marginX, y: marginY);
    final tr = BoundaryPoint(x: imageWidth - marginX, y: marginY);
    final br = BoundaryPoint(x: imageWidth - marginX, y: imageHeight - marginY);
    final bl = BoundaryPoint(x: marginX, y: imageHeight - marginY);
    return CardBoundary.fromCorners(
      topLeft: tl,
      topRight: tr,
      bottomRight: br,
      bottomLeft: bl,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      autoDetected: false,
    );
  }

  factory CardBoundary.fromCorners({
    required BoundaryPoint topLeft,
    required BoundaryPoint topRight,
    required BoundaryPoint bottomRight,
    required BoundaryPoint bottomLeft,
    required int imageWidth,
    required int imageHeight,
    double? segmentationConfidence,
    double? cardAreaRatio,
    bool autoDetected = true,
  }) {
    return CardBoundary(
      topLeft: topLeft,
      topRight: topRight,
      bottomRight: bottomRight,
      bottomLeft: bottomLeft,
      leftCurve1: topLeft.lerp(bottomLeft, 0.33),
      leftCurve2: topLeft.lerp(bottomLeft, 0.67),
      rightCurve1: topRight.lerp(bottomRight, 0.33),
      rightCurve2: topRight.lerp(bottomRight, 0.67),
      originalImageWidth: imageWidth,
      originalImageHeight: imageHeight,
      segmentationConfidence: segmentationConfidence,
      cardAreaRatio: cardAreaRatio,
      autoDetected: autoDetected,
    );
  }

  factory CardBoundary.fromBackendHandles({
    required Map<String, dynamic> handles,
    required int imageWidth,
    required int imageHeight,
    double? segmentationConfidence,
    double? cardAreaRatio,
  }) {
    BoundaryPoint point(String key, BoundaryPoint fallback) {
      final raw = handles[key];
      if (raw is Map<String, dynamic>) {
        return BoundaryPoint.fromJson(raw);
      }
      return fallback;
    }

    final fallback = CardBoundary.defaultForImage(
      imageWidth: imageWidth,
      imageHeight: imageHeight,
    );
    return CardBoundary.fromCorners(
      topLeft: point('TL', fallback.topLeft),
      topRight: point('TR', fallback.topRight),
      bottomRight: point('BR', fallback.bottomRight),
      bottomLeft: point('BL', fallback.bottomLeft),
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      segmentationConfidence: segmentationConfidence,
      cardAreaRatio: cardAreaRatio,
    );
  }

  final BoundaryPoint topLeft;
  final BoundaryPoint topRight;
  final BoundaryPoint bottomRight;
  final BoundaryPoint bottomLeft;
  final BoundaryPoint leftCurve1;
  final BoundaryPoint leftCurve2;
  final BoundaryPoint rightCurve1;
  final BoundaryPoint rightCurve2;
  final int originalImageWidth;
  final int originalImageHeight;
  final double? segmentationConfidence;
  final double? cardAreaRatio;
  final bool autoDetected;
  final bool manuallyCorrected;

  BoundaryPoint pointFor(BoundaryHandle handle) {
    return switch (handle) {
      BoundaryHandle.topLeft => topLeft,
      BoundaryHandle.topRight => topRight,
      BoundaryHandle.bottomRight => bottomRight,
      BoundaryHandle.bottomLeft => bottomLeft,
      BoundaryHandle.leftCurve1 => leftCurve1,
      BoundaryHandle.leftCurve2 => leftCurve2,
      BoundaryHandle.rightCurve1 => rightCurve1,
      BoundaryHandle.rightCurve2 => rightCurve2,
    };
  }

  CardBoundary copyWithPoint(BoundaryHandle handle, BoundaryPoint point) {
    return CardBoundary(
      topLeft: handle == BoundaryHandle.topLeft ? point : topLeft,
      topRight: handle == BoundaryHandle.topRight ? point : topRight,
      bottomRight: handle == BoundaryHandle.bottomRight ? point : bottomRight,
      bottomLeft: handle == BoundaryHandle.bottomLeft ? point : bottomLeft,
      leftCurve1: handle == BoundaryHandle.leftCurve1 ? point : leftCurve1,
      leftCurve2: handle == BoundaryHandle.leftCurve2 ? point : leftCurve2,
      rightCurve1: handle == BoundaryHandle.rightCurve1 ? point : rightCurve1,
      rightCurve2: handle == BoundaryHandle.rightCurve2 ? point : rightCurve2,
      originalImageWidth: originalImageWidth,
      originalImageHeight: originalImageHeight,
      segmentationConfidence: segmentationConfidence,
      cardAreaRatio: cardAreaRatio,
      autoDetected: autoDetected,
      manuallyCorrected: true,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'top_left': topLeft.toJson(),
      'top_right': topRight.toJson(),
      'bottom_right': bottomRight.toJson(),
      'bottom_left': bottomLeft.toJson(),
      'left_curve_1': leftCurve1.toJson(),
      'left_curve_2': leftCurve2.toJson(),
      'right_curve_1': rightCurve1.toJson(),
      'right_curve_2': rightCurve2.toJson(),
      'original_image_width': originalImageWidth,
      'original_image_height': originalImageHeight,
      'segmentation_confidence': segmentationConfidence,
      'card_area_ratio': cardAreaRatio,
      'auto_detected': autoDetected,
      'manually_corrected': manuallyCorrected,
    };
  }
}

class SegmentationResult {
  const SegmentationResult({
    required this.status,
    this.rectifiedImageBase64,
    this.boundary,
    this.confidence,
    this.cardAreaRatio,
    this.manualBoundaryRequired = false,
    this.manualBoundaryReason,
    this.errorMessage,
  });

  factory SegmentationResult.fromJson(Map<String, dynamic> json) {
    final segmentation = json['segmentation'] as Map<String, dynamic>?;
    final handles = segmentation?['handles'] as Map<String, dynamic>?;
    final imageWidth = (segmentation?['image_width'] as num?)?.toInt();
    final imageHeight = (segmentation?['image_height'] as num?)?.toInt();
    final confidence = (segmentation?['confidence'] as num?)?.toDouble();
    final areaRatio = (segmentation?['card_area_ratio'] as num?)?.toDouble();
    final boundary =
        handles == null || imageWidth == null || imageHeight == null
        ? null
        : CardBoundary.fromBackendHandles(
            handles: handles,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            segmentationConfidence: confidence,
            cardAreaRatio: areaRatio,
          );
    final backendManual =
        segmentation?['manual_boundary_required'] as bool? ?? false;
    final localManual =
        confidence == null ||
        confidence < ScanThresholds.segmentationConfidence ||
        (areaRatio ?? 0) < ScanThresholds.minCardImageAreaRatio;

    return SegmentationResult(
      status: json['status'] as String? ?? 'error',
      rectifiedImageBase64: json['rectified_image_base64'] as String?,
      boundary: boundary,
      confidence: confidence,
      cardAreaRatio: areaRatio,
      manualBoundaryRequired: backendManual || localManual,
      manualBoundaryReason:
          segmentation?['manual_boundary_reason'] as String? ??
          _manualReason(confidence, areaRatio),
      errorMessage:
          (json['error'] as Map<String, dynamic>?)?['message'] as String?,
    );
  }

  final String status;
  final String? rectifiedImageBase64;
  final CardBoundary? boundary;
  final double? confidence;
  final double? cardAreaRatio;
  final bool manualBoundaryRequired;
  final String? manualBoundaryReason;
  final String? errorMessage;

  static String? _manualReason(double? confidence, double? areaRatio) {
    if (confidence == null) {
      return 'segmentation_confidence_unavailable';
    }
    if (confidence < ScanThresholds.segmentationConfidence) {
      return 'low_segmentation_confidence';
    }
    if ((areaRatio ?? 0) < ScanThresholds.minCardImageAreaRatio) {
      return 'card_too_small_in_frame';
    }
    return null;
  }
}

class RectifiedCardImage {
  const RectifiedCardImage({required this.base64});

  final String base64;
}

class CenteringAnalysis {
  const CenteringAnalysis({
    required this.leftRight,
    required this.topBottom,
    required this.tiltPercent,
    required this.rank,
    this.confidence,
  });

  factory CenteringAnalysis.fromJson(Map<String, dynamic> json) {
    return CenteringAnalysis(
      leftRight: json['left_right'] as String? ?? '--',
      topBottom: json['top_bottom'] as String? ?? '--',
      tiltPercent: (json['tilt_percent'] as num?)?.toDouble() ?? 0,
      rank: json['rank'] as String? ?? 'A',
      confidence: json['confidence'] as String?,
    );
  }

  final String leftRight;
  final String topBottom;
  final double tiltPercent;
  final String rank;
  final String? confidence;
}

class CardCandidate {
  const CardCandidate({
    this.id,
    this.name,
    this.setName,
    this.setAbbreviation,
    this.cardNumber,
    this.imageUrl,
    this.confidence,
    this.marketValue,
    this.rarity,
    this.raw = const {},
  });

  factory CardCandidate.fromJson(Map<String, dynamic> json) {
    final raw = json['raw'] as Map<String, dynamic>? ?? const {};
    return CardCandidate(
      id:
          json['id']?.toString() ??
          raw['product_id']?.toString() ??
          raw['productId']?.toString(),
      name:
          json['name'] as String? ??
          raw['name'] as String? ??
          raw['product_name'] as String?,
      setName:
          json['set_name'] as String? ??
          raw['set_name'] as String? ??
          raw['setName'] as String?,
      setAbbreviation:
          json['set_abbreviation'] as String? ??
          raw['set_abbr'] as String? ??
          raw['setAbbr'] as String?,
      cardNumber:
          json['card_number'] as String? ??
          raw['ext_number']?.toString() ??
          raw['number']?.toString(),
      imageUrl:
          json['image_url'] as String? ??
          raw['image_url'] as String? ??
          raw['imageUrl'] as String?,
      confidence: (json['confidence'] as num?)?.toDouble(),
      marketValue: _marketValueFromJson(json, raw),
      rarity:
          json['rarity'] as String? ??
          raw['ext_rarity'] as String? ??
          raw['rarity'] as String?,
      raw: raw,
    );
  }

  final String? id;
  final String? name;
  final String? setName;
  final String? setAbbreviation;
  final String? cardNumber;
  final String? imageUrl;
  final double? confidence;
  final String? marketValue;
  final String? rarity;
  final Map<String, dynamic> raw;

  Map<String, Object?> toMatchJson() {
    return {
      'id': id,
      'name': name,
      'set_name': setName,
      'set_abbreviation': setAbbreviation,
      'card_number': cardNumber,
      'image_url': imageUrl,
      'confidence': confidence,
      'market_value': marketValue,
      'rarity': rarity,
      'raw': raw,
    };
  }

  static String? _marketValueFromJson(
    Map<String, dynamic> json,
    Map<String, dynamic> raw,
  ) {
    final explicit =
        json['market_value'] ??
        json['marketValue'] ??
        json['price_range'] ??
        json['priceRange'];
    if (explicit is String && explicit.trim().isNotEmpty) {
      return explicit.trim();
    }

    final rawMarket =
        raw['market_price'] ??
        raw['marketPrice'] ??
        raw['market'] ??
        raw['tcg_market'];
    final market = _doubleFromValue(rawMarket);
    if (market != null) {
      return '\$${market.toStringAsFixed(2)} market';
    }
    return null;
  }

  static double? _doubleFromValue(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      final cleaned = value.replaceAll(RegExp(r'[^0-9.]'), '');
      if (cleaned.isEmpty) {
        return null;
      }
      return double.tryParse(cleaned);
    }
    return null;
  }
}

class CardIdentificationResult {
  const CardIdentificationResult({
    required this.status,
    required this.manualSearchRequired,
    this.bestMatch,
    this.candidates = const [],
    this.confidenceScore,
    this.centering,
    this.errorMessage,
  });

  factory CardIdentificationResult.fromJson(Map<String, dynamic> json) {
    return CardIdentificationResult(
      status: json['status'] as String? ?? 'error',
      manualSearchRequired: json['manual_search_required'] as bool? ?? true,
      bestMatch: json['best_match'] is Map<String, dynamic>
          ? CardCandidate.fromJson(json['best_match'] as Map<String, dynamic>)
          : null,
      candidates: (json['matches'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(CardCandidate.fromJson)
          .toList(),
      confidenceScore: (json['confidence_score'] as num?)?.toDouble(),
      centering: json['centering'] is Map<String, dynamic>
          ? CenteringAnalysis.fromJson(
              json['centering'] as Map<String, dynamic>,
            )
          : null,
      errorMessage:
          (json['error'] as Map<String, dynamic>?)?['message'] as String?,
    );
  }

  final String status;
  final bool manualSearchRequired;
  final CardCandidate? bestMatch;
  final List<CardCandidate> candidates;
  final double? confidenceScore;
  final CenteringAnalysis? centering;
  final String? errorMessage;

  bool get isAccepted {
    final score = confidenceScore;
    return status == 'accepted' &&
        !manualSearchRequired &&
        score != null &&
        score >= ScanThresholds.cardIdentificationConfidence * 100;
  }
}

class BackendScanResult {
  const BackendScanResult({
    required this.status,
    required this.manualSearchRequired,
    this.rectifiedImageBase64,
    this.detectedCard,
    this.confidenceScore,
    this.segmentation,
    this.centering,
    this.errorMessage,
  });

  factory BackendScanResult.fromJson(Map<String, dynamic> json) {
    return BackendScanResult(
      status: json['status'] as String? ?? 'error',
      manualSearchRequired: json['manual_search_required'] as bool? ?? true,
      rectifiedImageBase64: json['segmented_image_base64'] as String?,
      detectedCard: json['detected_card_match'] is Map<String, dynamic>
          ? CardCandidate.fromJson(
              json['detected_card_match'] as Map<String, dynamic>,
            )
          : null,
      confidenceScore: (json['confidence_score'] as num?)?.toDouble(),
      segmentation: json['segmentation'] is Map<String, dynamic>
          ? SegmentationResult.fromJson({
              'status': 'ok',
              'segmentation': json['segmentation'],
            })
          : null,
      centering: json['centering'] is Map<String, dynamic>
          ? CenteringAnalysis.fromJson(
              json['centering'] as Map<String, dynamic>,
            )
          : null,
      errorMessage:
          (json['error'] as Map<String, dynamic>?)?['message'] as String?,
    );
  }

  final String status;
  final bool manualSearchRequired;
  final String? rectifiedImageBase64;
  final CardCandidate? detectedCard;
  final double? confidenceScore;
  final SegmentationResult? segmentation;
  final CenteringAnalysis? centering;
  final String? errorMessage;

  bool get isAccepted {
    final score = confidenceScore;
    return status == 'accepted' &&
        !manualSearchRequired &&
        score != null &&
        score >= ScanThresholds.cardIdentificationConfidence * 100;
  }
}

class SharePassportResult {
  const SharePassportResult({required this.imageBase64});

  final String imageBase64;
}
