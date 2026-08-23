import 'dart:typed_data';

import 'binder_repository_stub.dart'
    if (dart.library.html) 'binder_repository_web.dart'
    as implementation;

const binderSchemaVersion = 1;

class BinderImagePayload {
  const BinderImagePayload({required this.bytes, required this.mimeType});

  final Uint8List bytes;
  final String mimeType;
}

abstract class BinderRepository {
  Future<void> initialize();

  Future<List<Map<String, dynamic>>> loadCollections();

  Future<void> saveCollections(List<Map<String, dynamic>> collections);

  Future<List<Map<String, dynamic>>> loadSavedCards();

  Future<void> saveCard(
    Map<String, dynamic> savedCard, {
    BinderImagePayload? image,
    BinderImagePayload? thumbnail,
  });

  Future<void> deleteCard(String localId);

  Future<void> updateCard(Map<String, dynamic> savedCard);

  Future<void> moveCardToCollection(String localId, String collectionType);

  Future<BinderImagePayload?> getCardImage(String localImageKey);

  Future<BinderImagePayload?> getCardThumbnail(String localThumbnailKey);

  Future<String> saveImageBlob(BinderImagePayload image);

  Future<void> deleteImageBlob(String imageKey);
}

BinderRepository createBinderRepository() {
  return implementation.createBinderRepository();
}

class BinderStorageException implements Exception {
  const BinderStorageException(this.message);

  final String message;

  @override
  String toString() => message;
}
