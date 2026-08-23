import 'dart:convert';
import 'dart:typed_data';

import 'package:idb_shim/idb_browser.dart';

import 'binder_repository.dart';

BinderRepository createBinderRepository() => IndexedDbBinderRepository();

class IndexedDbBinderRepository implements BinderRepository {
  static const _dbName = 'sist_binder_db';
  static const _savedCardsStore = 'saved_cards';
  static const _imagesStore = 'card_images';
  static const _metadataStore = 'app_metadata';
  static const _collectionsKey = 'collections';
  static const _schemaKey = 'schemaVersion';

  Database? _db;

  @override
  Future<void> initialize() async {
    _db = await idbFactoryBrowser.open(
      _dbName,
      version: binderSchemaVersion,
      onUpgradeNeeded: (event) {
        final database = event.database;
        if (!database.objectStoreNames.contains(_savedCardsStore)) {
          database.createObjectStore(_savedCardsStore, keyPath: 'localId');
        }
        if (!database.objectStoreNames.contains(_imagesStore)) {
          database.createObjectStore(_imagesStore, keyPath: 'key');
        }
        if (!database.objectStoreNames.contains(_metadataStore)) {
          database.createObjectStore(_metadataStore, keyPath: 'key');
        }
      },
    );

    await _put(_metadataStore, {
      'key': _schemaKey,
      'value': binderSchemaVersion,
      'updatedAt': DateTime.now().toIso8601String(),
    });
  }

  @override
  Future<List<Map<String, dynamic>>> loadCollections() async {
    final record = await _get(_metadataStore, _collectionsKey);
    if (record is Map && record['value'] is List) {
      return (record['value'] as List)
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }
    final cards = await loadSavedCards();
    if (cards.isEmpty) {
      return [];
    }
    final now = DateTime.now().toIso8601String();
    return [
      {
        'id': 'binder',
        'name': 'Binder',
        'cards': cards,
        'createdAt': now,
        'updatedAt': now,
      },
    ];
  }

  @override
  Future<void> saveCollections(List<Map<String, dynamic>> collections) async {
    await _put(_metadataStore, {
      'key': _collectionsKey,
      'value': collections,
      'updatedAt': DateTime.now().toIso8601String(),
    });

    final activeIds = <String>{};
    for (final collection in collections) {
      final collectionId = collection['id']?.toString() ?? 'binder';
      final collectionName = collection['name']?.toString() ?? 'Binder';
      final rawCards = collection['cards'];
      if (rawCards is! List) {
        continue;
      }
      for (final rawCard in rawCards) {
        if (rawCard is! Map) {
          continue;
        }
        final savedCard = Map<String, dynamic>.from(rawCard)
          ..['collectionType'] = _collectionTypeForId(collectionId)
          ..['collectionId'] = collectionId
          ..['collectionName'] = collectionName
          ..['schemaVersion'] = rawCard['schemaVersion'] ?? binderSchemaVersion;
        final localId = savedCard['localId']?.toString();
        if (localId == null || localId.isEmpty) {
          continue;
        }
        activeIds.add(localId);
        await _put(_savedCardsStore, savedCard);
      }
    }

    final existing = await loadSavedCards();
    for (final card in existing) {
      final localId = card['localId']?.toString();
      if (localId != null && !activeIds.contains(localId)) {
        await deleteCard(localId);
      }
    }
  }

  @override
  Future<List<Map<String, dynamic>>> loadSavedCards() async {
    final db = _requireDb();
    final transaction = db.transaction(_savedCardsStore, idbModeReadOnly);
    final records = await transaction.objectStore(_savedCardsStore).getAll();
    return records
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  @override
  Future<void> saveCard(
    Map<String, dynamic> savedCard, {
    BinderImagePayload? image,
    BinderImagePayload? thumbnail,
  }) async {
    if (image != null) {
      savedCard['localImageKey'] ??= await saveImageBlob(image);
    }
    if (thumbnail != null) {
      savedCard['localThumbnailKey'] ??= await saveImageBlob(thumbnail);
    }
    savedCard['schemaVersion'] ??= binderSchemaVersion;
    await _put(_savedCardsStore, savedCard);
  }

  @override
  Future<void> deleteCard(String localId) async {
    final existing = await _get(_savedCardsStore, localId);
    await _delete(_savedCardsStore, localId);
    if (existing is Map) {
      await _deleteUnreferencedImage(existing['localImageKey']?.toString());
      await _deleteUnreferencedImage(existing['localThumbnailKey']?.toString());
      await _deleteUnreferencedImage(
        existing['originalScanImageKey']?.toString(),
      );
      await _deleteUnreferencedImage(
        existing['rectifiedScanImageKey']?.toString(),
      );
    }
  }

  @override
  Future<void> updateCard(Map<String, dynamic> savedCard) async {
    savedCard['updatedAt'] = DateTime.now().toIso8601String();
    await saveCard(savedCard);
  }

  @override
  Future<void> moveCardToCollection(
    String localId,
    String collectionType,
  ) async {
    final existing = await _get(_savedCardsStore, localId);
    if (existing is Map) {
      final updated = Map<String, dynamic>.from(existing)
        ..['collectionType'] = collectionType
        ..['updatedAt'] = DateTime.now().toIso8601String();
      await _put(_savedCardsStore, updated);
    }
  }

  @override
  Future<BinderImagePayload?> getCardImage(String localImageKey) {
    return _getImage(localImageKey);
  }

  @override
  Future<BinderImagePayload?> getCardThumbnail(String localThumbnailKey) {
    return _getImage(localThumbnailKey);
  }

  @override
  Future<String> saveImageBlob(BinderImagePayload image) async {
    final key = 'img-${DateTime.now().microsecondsSinceEpoch}';
    await _put(_imagesStore, {
      'key': key,
      'mimeType': image.mimeType,
      'bytes': image.bytes,
      'createdAt': DateTime.now().toIso8601String(),
    });
    return key;
  }

  @override
  Future<void> deleteImageBlob(String imageKey) async {
    await _delete(_imagesStore, imageKey);
  }

  Future<BinderImagePayload?> _getImage(String imageKey) async {
    final record = await _get(_imagesStore, imageKey);
    if (record is! Map) {
      return null;
    }
    final bytes = _bytesFromRecord(record['bytes']);
    if (bytes == null) {
      return null;
    }
    return BinderImagePayload(
      bytes: bytes,
      mimeType: record['mimeType']?.toString() ?? 'image/jpeg',
    );
  }

  Future<void> _deleteUnreferencedImage(String? imageKey) async {
    if (imageKey == null || imageKey.isEmpty) {
      return;
    }
    final cards = await loadSavedCards();
    final stillReferenced = cards.any((card) {
      return card['localImageKey'] == imageKey ||
          card['localThumbnailKey'] == imageKey ||
          card['originalScanImageKey'] == imageKey ||
          card['rectifiedScanImageKey'] == imageKey;
    });
    if (!stillReferenced) {
      await deleteImageBlob(imageKey);
    }
  }

  Future<Object?> _get(String storeName, Object key) async {
    final db = _requireDb();
    final transaction = db.transaction(storeName, idbModeReadOnly);
    return transaction.objectStore(storeName).getObject(key);
  }

  Future<void> _put(String storeName, Map<String, dynamic> value) async {
    final db = _requireDb();
    final transaction = db.transaction(storeName, idbModeReadWrite);
    await transaction.objectStore(storeName).put(value);
    await transaction.completed;
  }

  Future<void> _delete(String storeName, Object key) async {
    final db = _requireDb();
    final transaction = db.transaction(storeName, idbModeReadWrite);
    await transaction.objectStore(storeName).delete(key);
    await transaction.completed;
  }

  Database _requireDb() {
    final db = _db;
    if (db == null) {
      throw const BinderStorageException('Binder storage is not initialized.');
    }
    return db;
  }

  Uint8List? _bytesFromRecord(Object? value) {
    if (value is Uint8List) {
      return value;
    }
    if (value is ByteBuffer) {
      return Uint8List.view(value);
    }
    if (value is List) {
      return Uint8List.fromList(value.cast<int>());
    }
    if (value is String) {
      final commaIndex = value.indexOf(',');
      final payload = commaIndex >= 0 ? value.substring(commaIndex + 1) : value;
      return base64Decode(payload);
    }
    return null;
  }

  String _collectionTypeForId(String id) {
    return switch (id) {
      'wishlist' => 'wishlist',
      'grading_candidate' => 'grading_candidate',
      'trade_sell' => 'trade_sell',
      _ => 'binder',
    };
  }
}
