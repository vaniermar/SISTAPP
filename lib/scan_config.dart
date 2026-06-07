class ScanThresholds {
  const ScanThresholds._();

  static const segmentationConfidence = 0.85;
  static const cardIdentificationConfidence = 0.50;
  static const minCardImageAreaRatio = 0.30;
}

class ScanApiConfig {
  const ScanApiConfig._();

  static const baseUrl = String.fromEnvironment(
    'SIST_API_BASE_URL',
    defaultValue: '',
  );

  // This is only for protected local/internal deployments. Do not use this as
  // a real public-web secret; put auth or a proxy in front of the API instead.
  static const apiToken = String.fromEnvironment('SIST_API_TOKEN');
}
