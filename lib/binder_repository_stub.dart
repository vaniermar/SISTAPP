import 'binder_repository.dart';

BinderRepository createBinderRepository() => MemoryBinderRepository();

class MemoryBinderRepository implements BinderRepository {
  final Map<String, Map<String, dynamic>> _cards = {};
  final Map<String, BinderImagePayload> _images = {};
  List<Map<String, dynamic>> _collections = const [];

  @override
  Future<void> initialize() async {}

  @override
  Future<List<Map<String, dynamic>>> loadCollections() async {
    return _deepListCopy(_collections);
  }

  @override
  Future<void> saveCollections(List<Map<String, dynamic>> collections) async {
    _collections = _deepListCopy(collections);
    _cards
      ..clear()
      ..addEntries(
        _cardsFromCollections(_collections)
            .map((card) {
              return MapEntry(card['localId']?.toString() ?? '', card);
            })
            .where((entry) => entry.key.isNotEmpty),
      );
  }

  @override
  Future<List<Map<String, dynamic>>> loadSavedCards() async {
    return _cards.values
        .map((card) => Map<String, dynamic>.from(card))
        .toList();
  }

  @override
  Future<void> saveCard(
    Map<String, dynamic> savedCard, {
    BinderImagePayload? image,
    BinderImagePayload? thumbnail,
  }) async {
    final localId = savedCard['localId']?.toString();
    if (localId == null || localId.isEmpty) {
      throw const BinderStorageException('Saved card is missing a local id.');
    }
    _cards[localId] = Map<String, dynamic>.from(savedCard);
    if (image != null) {
      _images[savedCard['localImageKey']?.toString() ?? ''] = image;
    }
    if (thumbnail != null) {
      _images[savedCard['localThumbnailKey']?.toString() ?? ''] = thumbnail;
    }
  }

  @override
  Future<void> deleteCard(String localId) async {
    _cards.remove(localId);
  }

  @override
  Future<void> updateCard(Map<String, dynamic> savedCard) async {
    await saveCard(savedCard);
  }

  @override
  Future<void> moveCardToCollection(
    String localId,
    String collectionType,
  ) async {
    final card = _cards[localId];
    if (card != null) {
      card['collectionType'] = collectionType;
      card['updatedAt'] = DateTime.now().toIso8601String();
    }
  }

  @override
  Future<BinderImagePayload?> getCardImage(String localImageKey) async {
    return _images[localImageKey];
  }

  @override
  Future<BinderImagePayload?> getCardThumbnail(String localThumbnailKey) async {
    return _images[localThumbnailKey];
  }

  @override
  Future<String> saveImageBlob(BinderImagePayload image) async {
    final key = 'memory-image-${DateTime.now().microsecondsSinceEpoch}';
    _images[key] = image;
    return key;
  }

  @override
  Future<void> deleteImageBlob(String imageKey) async {
    _images.remove(imageKey);
  }
}

List<Map<String, dynamic>> _deepListCopy(List<Map<String, dynamic>> value) {
  return value.map((item) => Map<String, dynamic>.from(item)).toList();
}

Iterable<Map<String, dynamic>> _cardsFromCollections(
  List<Map<String, dynamic>> collections,
) sync* {
  for (final collection in collections) {
    final cards = collection['cards'];
    if (cards is! List) {
      continue;
    }
    for (final card in cards) {
      if (card is Map<String, dynamic>) {
        yield card;
      }
    }
  }
}
