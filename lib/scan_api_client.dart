import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'scan_config.dart';
import 'scan_models.dart';

class ScanApiException implements Exception {
  const ScanApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class BackendScanClient {
  BackendScanClient({
    http.Client? client,
    this.baseUrl = ScanApiConfig.baseUrl,
    this.apiToken = ScanApiConfig.apiToken,
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;
  final String apiToken;

  Uri _uri(String path) {
    final effectiveBaseUrl = baseUrl.isEmpty
        ? '${Uri.base.scheme}://${Uri.base.host}:8000'
        : baseUrl;
    final normalizedBase = effectiveBaseUrl.endsWith('/')
        ? effectiveBaseUrl.substring(0, effectiveBaseUrl.length - 1)
        : effectiveBaseUrl;
    return Uri.parse('$normalizedBase$path');
  }

  Map<String, String> get _headers {
    return {if (apiToken.isNotEmpty) 'x-sist-api-key': apiToken};
  }

  Map<String, String> get _jsonHeaders {
    return {'content-type': 'application/json', ..._headers};
  }

  Future<SegmentationResult> segmentImage({
    required Uint8List bytes,
    required String filename,
  }) async {
    final request = http.MultipartRequest('POST', _uri('/segment'))
      ..headers.addAll(_headers)
      ..files.add(
        http.MultipartFile.fromBytes('image', bytes, filename: filename),
      );
    final response = await http.Response.fromStream(
      await _client.send(request).timeout(const Duration(seconds: 60)),
    );
    final json = _decodeResponse(response);
    return SegmentationResult.fromJson(json);
  }

  Future<BackendScanResult> scanImageQueued({
    required Uint8List bytes,
    required String filename,
    void Function(String status)? onStatus,
  }) async {
    final request = http.MultipartRequest('POST', _uri('/jobs/scan'))
      ..headers.addAll(_headers)
      ..files.add(
        http.MultipartFile.fromBytes('image', bytes, filename: filename),
      );
    final createResponse = await http.Response.fromStream(
      await _client.send(request).timeout(const Duration(seconds: 60)),
    );
    final created = _decodeResponse(createResponse);
    final jobId = created['id'] as String?;
    if (jobId == null || jobId.isEmpty) {
      throw const ScanApiException('Scan job did not return a job id.');
    }

    for (var attempts = 0; attempts < 90; attempts++) {
      final pollResponse = await _client
          .get(_uri('/jobs/$jobId'), headers: _headers)
          .timeout(const Duration(seconds: 20));
      final job = _decodeResponse(pollResponse);
      final status = job['status'] as String? ?? 'queued';
      onStatus?.call(status);

      if (status == 'succeeded') {
        final result = job['result'];
        if (result is Map<String, dynamic>) {
          return BackendScanResult.fromJson(result);
        }
        throw const ScanApiException('Scan job succeeded without a result.');
      }

      if (status == 'failed') {
        final message =
            (job['error'] as Map<String, dynamic>?)?['message'] as String? ??
            'Scan job failed.';
        throw ScanApiException(message);
      }

      await Future<void>.delayed(const Duration(seconds: 1));
    }

    throw const ScanApiException('Scan job timed out.');
  }

  Future<RectifiedCardImage> rectifyImage({
    required String originalImageBase64,
    required CardBoundary boundary,
  }) async {
    final response = await _client
        .post(
          _uri('/rectify'),
          headers: _jsonHeaders,
          body: jsonEncode({
            'image_base64': originalImageBase64,
            'boundary': boundary.toJson(),
          }),
        )
        .timeout(const Duration(seconds: 60));
    final json = _decodeResponse(response);
    if (json['status'] != 'ok') {
      throw ScanApiException(_errorMessage(json, 'Rectification failed.'));
    }
    final image = json['rectified_image_base64'] as String?;
    if (image == null || image.isEmpty) {
      throw const ScanApiException('Rectification did not return an image.');
    }
    return RectifiedCardImage(base64: image);
  }

  Future<CardIdentificationResult> identifyCard(
    String rectifiedImageBase64,
  ) async {
    final response = await _client
        .post(
          _uri('/identify'),
          headers: _jsonHeaders,
          body: jsonEncode({'rectified_image_base64': rectifiedImageBase64}),
        )
        .timeout(const Duration(seconds: 60));
    return CardIdentificationResult.fromJson(_decodeResponse(response));
  }

  Future<CenteringAnalysis?> analyzeCentering({
    required String rectifiedImageBase64,
    required CardCandidate? match,
  }) async {
    final response = await _client
        .post(
          _uri('/centering'),
          headers: _jsonHeaders,
          body: jsonEncode({
            'rectified_image_base64': rectifiedImageBase64,
            'match': match?.toMatchJson(),
          }),
        )
        .timeout(const Duration(seconds: 60));
    final json = _decodeResponse(response);
    if (json['status'] != 'ok') {
      return null;
    }
    final centering = json['centering'];
    return centering is Map<String, dynamic>
        ? CenteringAnalysis.fromJson(centering)
        : null;
  }

  Future<SharePassportResult> renderPassport({
    required String rectifiedImageBase64,
    required String cardName,
    required String setName,
    required String cardNumber,
    required String marketValue,
    required String topBottom,
    required String leftRight,
    required String tilt,
    required String rank,
  }) async {
    final response = await _client
        .post(
          _uri('/passport'),
          headers: _jsonHeaders,
          body: jsonEncode({
            'rectified_image_base64': rectifiedImageBase64,
            'metadata': {
              'card_name': cardName,
              'set_name': setName,
              'card_number': cardNumber,
              'raw_price': marketValue,
              'status': 'Scanned Passport',
            },
            'centering': {
              'left_right': leftRight,
              'top_bottom': topBottom,
              'tilt_percent': _parseTilt(tilt),
              'rank': rank,
            },
          }),
        )
        .timeout(const Duration(seconds: 90));
    final json = _decodeResponse(response);
    if (json['status'] != 'ok') {
      throw ScanApiException(_errorMessage(json, 'Passport render failed.'));
    }
    final image = json['passport_image_base64'] as String?;
    if (image == null || image.isEmpty) {
      throw const ScanApiException('Passport render did not return an image.');
    }
    return SharePassportResult(imageBase64: image);
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ScanApiException(
        'Backend request failed with HTTP ${response.statusCode}.',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    throw const ScanApiException('Backend returned an unexpected response.');
  }

  String _errorMessage(Map<String, dynamic> json, String fallback) {
    return (json['error'] as Map<String, dynamic>?)?['message'] as String? ??
        fallback;
  }

  double? _parseTilt(String tilt) {
    final cleaned = tilt.replaceAll('%', '').trim();
    return double.tryParse(cleaned);
  }
}
