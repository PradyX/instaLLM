import 'package:flutter/material.dart';
import 'package:installm/features/bots/domain/bot.dart';
import 'package:installm/features/bots/domain/built_in_bots.dart';
import 'package:installm/features/profile_images/domain/petdex_pet.dart';
import 'package:installm/features/profile_images/presentation/bot_portrait_picker.dart';
import 'package:installm/i18n/strings.g.dart';

class BotDraft {
  const BotDraft(this.name, this.portrait, {this.templateId, this.soul = ''});
  final String name;
  final PetdexPet? portrait;
  final String? templateId;
  final String soul;
}

Future<BotDraft?> showCreateBotSheet(BuildContext context) =>
    showModalBottomSheet<BotDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 600),
      backgroundColor: Theme.of(context).colorScheme.surface.withAlpha(255),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      clipBehavior: Clip.antiAlias,
      builder: (_) => const CreateBotDialog(),
    );

/// One creation sheet; portrait, name, template and Soul stay drafts until Create.
class CreateBotDialog extends StatefulWidget {
  const CreateBotDialog({super.key});

  @override
  State<CreateBotDialog> createState() => _CreateBotDialogState();
}

class _CreateBotDialogState extends State<CreateBotDialog> {
  final _name = TextEditingController();
  late final _soul = TextEditingController(text: t.botCreation.starterSoul);
  final _draftSouls = <String?, String>{};
  PetdexPet? _portrait;
  String? _templateId;
  bool _portraitBusy = false;

  @override
  void dispose() {
    _name.dispose();
    _soul.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty || _portraitBusy) return;
    Navigator.of(
      context,
    ).pop(BotDraft(name, _portrait, templateId: _templateId, soul: _soul.text));
  }

  void _chooseTemplate(String? id) {
    _draftSouls[_templateId] = _soul.text;
    setState(() {
      _templateId = id;
      _soul.text =
          _draftSouls[id] ??
          (id == null ? t.botCreation.starterSoul : BuiltInBots.byId(id)!.soul);
    });
  }

  InputDecoration _field(String label) => InputDecoration(
    labelText: label,
    filled: true,
    counterText: '',
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
  );

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    return AnimatedPadding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      duration: const Duration(milliseconds: 160),
      child: LayoutBuilder(
        builder: (context, constraints) => SizedBox(
          height: (constraints.maxHeight * 0.95).clamp(0, 720),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        t.botCreation.title,
                        style: text.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: t.common.close,
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded, size: 20),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      BotPortraitPicker(
                        selected: _portrait,
                        onSelected: (pet) => setState(() => _portrait = pet),
                        onBusyChanged: (busy) =>
                            setState(() => _portraitBusy = busy),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        key: const ValueKey('bot-name'),
                        controller: _name,
                        maxLength: BotLimits.maxNameCharacters,
                        textCapitalization: TextCapitalization.words,
                        decoration: _field(t.botCreation.name),
                        onChanged: (_) => setState(() {}),
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String?>(
                        key: const ValueKey('bot-template'),
                        isExpanded: true,
                        initialValue: _templateId,
                        decoration: _field(t.botCreation.template),
                        items: [
                          DropdownMenuItem<String?>(
                            value: null,
                            child: Text(t.botCreation.noTemplate),
                          ),
                          for (final template in BuiltInBots.all())
                            DropdownMenuItem(
                              value: template.id,
                              child: Text(template.name),
                            ),
                        ],
                        onChanged: _chooseTemplate,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        t.botCreation.templateHint,
                        style: text.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        key: const ValueKey('bot-soul'),
                        controller: _soul,
                        minLines: 3,
                        maxLines: 5,
                        maxLength: BotLimits.maxSoulCharacters,
                        decoration: _field(t.botCreation.soul),
                        style: text.bodyMedium?.copyWith(height: 1.5),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        t.botCreation.soulHint,
                        style: text.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                  child: OverflowBar(
                    alignment: MainAxisAlignment.end,
                    spacing: 12,
                    overflowSpacing: 8,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(t.common.cancel),
                      ),
                      FilledButton.icon(
                        onPressed: _name.text.trim().isEmpty || _portraitBusy
                            ? null
                            : _submit,
                        icon: _portraitBusy
                            ? const SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.add_rounded, size: 18),
                        label: Text(t.botCreation.create),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
