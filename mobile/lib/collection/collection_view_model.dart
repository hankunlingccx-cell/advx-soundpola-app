import 'dart:convert';

import '../data/sound_repository.dart';

class CollectionScenePayload {
  CollectionScenePayload({
    required this.categories,
    this.editMode = false,
    this.reduceMotion = false,
  });

  final List<Map<String, dynamic>> categories;
  final bool editMode;
  final bool reduceMotion;

  Map<String, dynamic> toJson() => {
        'type': 'set_collection',
        'payload': {
          'categories': categories,
          'editMode': editMode,
          'reduceMotion': reduceMotion,
        },
      };

  String encode() => jsonEncode(toJson());
}

class CollectionViewModel {
  CollectionViewModel({SoundRepository? repo})
      : _repo = repo ?? SoundRepository.instance;

  final SoundRepository _repo;

  Future<CollectionScenePayload> buildPayload({
    bool editMode = false,
    bool reduceMotion = false,
  }) async {
    final groups = _repo.collectionGroups;
    final categories = <Map<String, dynamic>>[];

    for (final group in groups) {
      final cards = <Map<String, dynamic>>[];
      for (final card in group.items) {
        cards.add({
          'soundId': card.id,
          'name': card.title,
          'recordedAt': card.recordedAt.toUtc().toIso8601String(),
          'locationName': card.locationLabel,
          'visualSeed': card.visualSeed,
        });
      }
      categories.add({
        'id': group.category,
        'name': group.category,
        'cards': cards,
      });
    }

    return CollectionScenePayload(
      categories: categories,
      editMode: editMode,
      reduceMotion: reduceMotion,
    );
  }
}
