import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:installm/features/profile_images/data/petdex_service.dart';
import 'package:installm/features/profile_images/domain/petdex_pet.dart';

final petdexServiceProvider = FutureProvider<PetdexService>((ref) async {
  final support = await getApplicationSupportDirectory();
  final service = PetdexService(
    directory: Directory(p.join(support.path, 'profile_images')),
    dio: Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 20),
      ),
    ),
  );
  ref.onDispose(service.close);
  return service;
});

final profileImagesProvider =
    AsyncNotifierProvider<ProfileImagesController, Map<String, PetdexPet>>(
      ProfileImagesController.new,
    );

class ProfileImagesController extends AsyncNotifier<Map<String, PetdexPet>> {
  @override
  Future<Map<String, PetdexPet>> build() async =>
      (await ref.watch(petdexServiceProvider.future)).store.load();

  Future<bool> select(String key, PetdexPet? pet) async {
    try {
      await future;
      final service = await ref.read(petdexServiceProvider.future);
      final next = Map<String, PetdexPet>.from(
        state.valueOrNull ?? service.store.load(),
      );
      if (pet == null) {
        next.remove(key);
      } else {
        next[key] = pet;
      }
      if (!service.store.save(next)) return false;
      state = AsyncData(next);
      return true;
    } catch (_) {
      return false;
    }
  }
}

final petdexCatalogProvider = FutureProvider.autoDispose<List<PetdexPet>>((
  ref,
) async {
  final token = CancelToken();
  ref.onDispose(token.cancel);
  return (await ref.watch(
    petdexServiceProvider.future,
  )).catalog(cancelToken: token);
});

final petdexImageProvider = FutureProvider.autoDispose.family<File, PetdexPet>((
  ref,
  pet,
) async {
  final token = CancelToken();
  ref.onDispose(token.cancel);
  return (await ref.watch(
    petdexServiceProvider.future,
  )).image(pet, cancelToken: token);
});
