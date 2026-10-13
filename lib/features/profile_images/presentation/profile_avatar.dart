import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:installm/core/widgets/default_bot_avatar.dart';
import 'package:installm/features/profile_images/application/profile_images_controller.dart';
import 'package:installm/features/profile_images/domain/petdex_pet.dart';

/// Shared by the sidebar, header, member list and picker. Never fetches the
/// catalog: the default bot mark or a room's member stack needs no networking.
class ProfileAvatar extends ConsumerWidget {
  const ProfileAvatar({
    super.key,
    required this.profileKey,
    this.fallback,
    this.size = 32,
  });

  final String profileKey;
  final Widget? fallback;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pet = ref.watch(profileImagesProvider).valueOrNull?[profileKey];
    final defaultImage = fallback ?? DefaultBotAvatar(size: size);
    return pet == null
        ? SizedBox.square(
            dimension: size,
            child: Center(child: defaultImage),
          )
        : PetdexAvatar(pet: pet, fallback: defaultImage, size: size);
  }
}

class PetdexAvatar extends ConsumerWidget {
  const PetdexAvatar({
    super.key,
    required this.pet,
    required this.fallback,
    this.size = 48,
  });

  final PetdexPet pet;
  final Widget fallback;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final file = ref.watch(petdexImageProvider(pet)).valueOrNull;
    return SizedBox.square(
      dimension: size,
      child: file == null
          ? Center(child: fallback)
          : Image.file(
              file,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => Center(child: fallback),
            ),
    );
  }
}
