import 'dart:convert';

import '../data/sound_repository.dart';
import 'sound_texture_baker.dart';

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
    final trays = _repo.collectionTrays;
    final categories = <Map<String, dynamic>>[];

    for (final tray in trays) {
      final cards = <Map<String, dynamic>>[];
      for (final card in tray.cards) {
        final texture = card.frontTextureUrl ??
            await SoundTextureBaker.bakeFrontDataUrl(card.visualSeed);
        cards.add({
          'soundId': card.id,
          'name': card.title,
          'recordedAt': card.recordedAt.toUtc().toIso8601String(),
          'locationName': card.locationLabel,
          'frontTextureUrl': texture,
          'visualSeed': card.visualSeed,
        });
      }
      categories.add({
        'id': tray.category.id,
        'name': tray.category.name,
        'accentColor': tray.category.accentColor,
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
