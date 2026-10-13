import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocket_llm/features/profile_images/application/profile_images_controller.dart';
import 'package:pocket_llm/features/profile_images/data/petdex_service.dart';
import 'package:pocket_llm/features/profile_images/domain/petdex_pet.dart';
import 'package:pocket_llm/features/profile_images/presentation/profile_avatar.dart';
import 'package:pocket_llm/i18n/strings.g.dart';

class ProfileImageButton extends StatelessWidget {
  const ProfileImageButton({
    super.key,
    required this.profileKey,
    this.fallback,
  });

  final String profileKey;
  final Widget? fallback;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: ProfileAvatar(
      profileKey: profileKey,
      fallback: fallback,
      size: 48,
    ),
    title: Text(t.profileImages.title),
    trailing: OutlinedButton(
      onPressed: () => showDialog<void>(
        context: context,
        builder: (_) => ProfileImagePicker(profileKey: profileKey),
      ),
      child: Text(t.profileImages.choose),
    ),
  );
}

class ProfileImagePicker extends ConsumerStatefulWidget {
  const ProfileImagePicker({super.key, required this.profileKey})
    : initialSelection = null;

  /// Returns a draft without saving an override. Null means cancellation;
  /// a selection with a null pet means the user chose the default icon.
  const ProfileImagePicker.draft({super.key, this.initialSelection})
    : profileKey = null;

  final String? profileKey;
  final PetdexPet? initialSelection;

  @override
  ConsumerState<ProfileImagePicker> createState() => _ProfileImagePickerState();
}

class _ProfileImagePickerState extends ConsumerState<ProfileImagePicker> {
  Timer? _debounce;
  var _query = '';
  var _saving = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _select(PetdexPet? pet) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      // A chosen portrait must be cached successfully before it is saved.
      if (pet != null) {
        final provider = petdexImageProvider(pet);
        if (ref.read(provider).hasError) ref.invalidate(provider);
        await ref.read(provider.future);
      }
      if (!mounted) return;
      final key = widget.profileKey;
      if (key == null) {
        Navigator.of(context).pop(ProfileImageSelection(pet));
        return;
      }
      final saved = await ref
          .read(profileImagesProvider.notifier)
          .select(key, pet);
      if (!mounted) return;
      if (saved) {
        Navigator.of(context).pop();
      } else {
        setState(() => _error = t.profileImages.saveError);
      }
    } catch (_) {
      if (mounted) setState(() => _error = t.profileImages.imageError);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.profileKey == null
        ? widget.initialSelection
        : ref.watch(profileImagesProvider).valueOrNull?[widget.profileKey];
    // No catalog request and no thumbnail requests until the user searches.
    final catalog = _query.isEmpty ? null : ref.watch(petdexCatalogProvider);
    return AlertDialog(
      scrollable: true,
      title: Text(t.profileImages.pickerTitle),
      content: SizedBox(
        width: 560,
        height: MediaQuery.sizeOf(context).height * 0.58,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t.profileImages.networkHint,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              autofocus: true,
              decoration: InputDecoration(
                labelText: t.profileImages.search,
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
              ),
              onChanged: (value) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 350), () {
                  if (mounted) setState(() => _query = value.trim());
                });
              },
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (_saving) const LinearProgressIndicator(),
            const SizedBox(height: 12),
            Expanded(
              child: catalog == null
                  ? Center(
                      child: selected == null
                          ? Text(t.profileImages.startSearch)
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                PetdexAvatar(
                                  pet: selected,
                                  fallback: const Icon(Icons.pets_outlined),
                                  size: 88,
                                ),
                                Text(selected.name),
                              ],
                            ),
                    )
                  : catalog.when(
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (_, _) => Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(t.profileImages.catalogError),
                            TextButton(
                              onPressed: () =>
                                  ref.invalidate(petdexCatalogProvider),
                              child: Text(t.profileImages.retry),
                            ),
                          ],
                        ),
                      ),
                      data: (pets) {
                        final matches = PetdexService.search(pets, _query);
                        if (matches.isEmpty) {
                          return Center(child: Text(t.profileImages.noResults));
                        }
                        return GridView.builder(
                          key: ValueKey(_query),
                          scrollCacheExtent: const ScrollCacheExtent.pixels(0),
                          gridDelegate:
                              SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 140,
                                mainAxisExtent:
                                    108 +
                                    MediaQuery.textScalerOf(context).scale(32),
                                crossAxisSpacing: 8,
                                mainAxisSpacing: 8,
                              ),
                          itemCount: matches.length,
                          itemBuilder: (context, index) {
                            final pet = matches[index];
                            return Tooltip(
                              message: pet.creator.isEmpty
                                  ? pet.name
                                  : '${pet.name} · ${pet.creator}',
                              child: Card(
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: _saving ? null : () => _select(pet),
                                  child: Padding(
                                    padding: const EdgeInsets.all(8),
                                    child: Column(
                                      children: [
                                        PetdexAvatar(
                                          pet: pet,
                                          fallback: const Icon(
                                            Icons.pets_outlined,
                                          ),
                                          size: 72,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          pet.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        if (pet.creator.isNotEmpty)
                                          Text(
                                            pet.creator,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(
                                              context,
                                            ).textTheme.bodySmall,
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        if (selected != null)
          TextButton(
            onPressed: _saving ? null : () => _select(null),
            child: Text(t.profileImages.useDefault),
          ),
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text(t.common.close),
        ),
      ],
    );
  }
}

class ProfileImageSelection {
  const ProfileImageSelection(this.pet);
  final PetdexPet? pet;
}
