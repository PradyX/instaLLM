import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:installm/core/widgets/default_bot_avatar.dart';
import 'package:installm/features/profile_images/application/profile_images_controller.dart';
import 'package:installm/features/profile_images/data/petdex_service.dart';
import 'package:installm/features/profile_images/domain/petdex_pet.dart';
import 'package:installm/features/profile_images/presentation/profile_avatar.dart';
import 'package:installm/i18n/strings.g.dart';

/// An inline, cancellable portrait choice. Only Create saves a profile record.
class BotPortraitPicker extends ConsumerStatefulWidget {
  const BotPortraitPicker({
    super.key,
    required this.selected,
    required this.onSelected,
    required this.onBusyChanged,
  });

  final PetdexPet? selected;
  final ValueChanged<PetdexPet?> onSelected;
  final ValueChanged<bool> onBusyChanged;

  @override
  ConsumerState<BotPortraitPicker> createState() => _BotPortraitPickerState();
}

class _BotPortraitPickerState extends ConsumerState<BotPortraitPicker> {
  final _scroll = ScrollController();
  Timer? _debounce;
  String _query = '';
  String? _error;
  int _request = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _select(PetdexPet? pet) async {
    final request = ++_request;
    setState(() => _error = null);
    if (pet == null) {
      widget.onSelected(null);
      widget.onBusyChanged(false);
      return;
    }
    widget.onBusyChanged(true);
    try {
      final provider = petdexImageProvider(pet);
      if (ref.read(provider).hasError) ref.invalidate(provider);
      await ref.read(provider.future);
      if (mounted && request == _request) widget.onSelected(pet);
    } catch (_) {
      if (mounted && request == _request) {
        setState(() => _error = t.profileImages.imageError);
      }
    } finally {
      if (mounted && request == _request) widget.onBusyChanged(false);
    }
  }

  void _slide(int direction) {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    _scroll.animateTo(
      (position.pixels + direction * position.viewportDimension * 0.8).clamp(
        0,
        position.maxScrollExtent,
      ),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final catalog = ref.watch(petdexCatalogProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            widget.selected == null
                ? const DefaultBotAvatar(size: 48)
                : PetdexAvatar(
                    pet: widget.selected!,
                    fallback: const DefaultBotAvatar(size: 48),
                  ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.profileImages.title, style: text.titleSmall),
                  Text(
                    widget.selected?.name ?? t.botCreation.defaultPortrait,
                    style: text.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (widget.selected != null)
              IconButton(
                tooltip: t.profileImages.useDefault,
                onPressed: () => _select(null),
                icon: const Icon(Icons.restart_alt_rounded, size: 20),
              ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('bot-portrait-search'),
          decoration: InputDecoration(
            hintText: t.botCreation.searchPortraits,
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            filled: true,
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onChanged: (value) {
            _debounce?.cancel();
            _debounce = Timer(const Duration(milliseconds: 250), () {
              if (!mounted) return;
              if (_scroll.hasClients) _scroll.jumpTo(0);
              setState(() => _query = value.trim());
            });
          },
        ),
        const SizedBox(height: 10),
        catalog.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          error: (_, _) => Row(
            children: [
              Expanded(
                child: Text(
                  t.botCreation.portraitsOffline,
                  style: text.bodySmall,
                ),
              ),
              IconButton(
                tooltip: t.profileImages.retry,
                onPressed: () => ref.invalidate(petdexCatalogProvider),
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          data: (pets) {
            final matches = _query.isEmpty
                ? PetdexService.featured(pets)
                : PetdexService.search(pets, _query);
            if (matches.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(t.profileImages.noResults, style: text.bodySmall),
              );
            }
            final scale = MediaQuery.textScalerOf(context).scale(12) / 12;
            return SizedBox(
              height: 78 + MediaQuery.textScalerOf(context).scale(22),
              child: ListView.separated(
                key: const ValueKey('bot-portrait-carousel'),
                controller: _scroll,
                scrollDirection: Axis.horizontal,
                scrollCacheExtent: const ScrollCacheExtent.pixels(0),
                itemCount: matches.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final pet = matches[index];
                  final selected = widget.selected == pet;
                  return SizedBox(
                    width: 88 * scale.clamp(1, 1.4),
                    child: Tooltip(
                      message: pet.name,
                      child: Semantics(
                        selected: selected,
                        button: true,
                        child: Material(
                          color: selected
                              ? colors.primaryContainer
                              : colors.surfaceContainerLow,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: selected
                                  ? colors.primary
                                  : colors.outlineVariant,
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            key: ValueKey('bot-portrait-${pet.slug}'),
                            onTap: () => _select(pet),
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Column(
                                children: [
                                  PetdexAvatar(
                                    pet: pet,
                                    size: 56,
                                    fallback: const Icon(Icons.pets_outlined),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    pet.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: text.labelSmall,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
        Row(
          children: [
            Expanded(
              child: Text(
                t.botCreation.portraitHint,
                style: text.labelSmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
            IconButton(
              tooltip: t.botCreation.previousPortraits,
              onPressed: catalog.hasValue ? () => _slide(-1) : null,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.chevron_left_rounded, size: 20),
            ),
            IconButton(
              tooltip: t.botCreation.nextPortraits,
              onPressed: catalog.hasValue ? () => _slide(1) : null,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.chevron_right_rounded, size: 20),
            ),
          ],
        ),
        if (_error != null)
          Text(_error!, style: text.bodySmall?.copyWith(color: colors.error)),
      ],
    );
  }
}
