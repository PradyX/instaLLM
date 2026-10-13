import 'package:flutter/material.dart';
import 'package:installm/core/widgets/default_bot_avatar.dart';
import 'package:installm/features/bots/domain/built_in_bots.dart';
import 'package:installm/features/profile_images/domain/petdex_pet.dart';
import 'package:installm/features/profile_images/presentation/profile_avatar.dart';
import 'package:installm/features/profile_images/presentation/profile_image_picker.dart';
import 'package:installm/i18n/strings.g.dart';

class BotDraft {
  const BotDraft(this.name, this.portrait, {this.templateId});
  final String name;
  final PetdexPet? portrait;
  final String? templateId;
}

/// Owns the name controller and cosmetic draft until creation is confirmed.
class CreateBotDialog extends StatefulWidget {
  const CreateBotDialog({super.key});

  @override
  State<CreateBotDialog> createState() => _CreateBotDialogState();
}

class _CreateBotDialogState extends State<CreateBotDialog> {
  final _name = TextEditingController();
  PetdexPet? _portrait;
  String? _templateId;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isNotEmpty) {
      Navigator.of(
        context,
      ).pop(BotDraft(name, _portrait, templateId: _templateId));
    }
  }

  Future<void> _choose() async {
    final choice = await showDialog<ProfileImageSelection>(
      context: context,
      builder: (_) => ProfileImagePicker.draft(initialSelection: _portrait),
    );
    if (mounted && choice != null) setState(() => _portrait = choice.pet);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text(t.botCreation.title),
    content: SizedBox(
      width: 360,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String?>(
            isExpanded: true,
            initialValue: _templateId,
            decoration: InputDecoration(labelText: t.botCreation.startWith),
            items: [
              DropdownMenuItem<String?>(
                value: null,
                child: Text(t.botCreation.blank),
              ),
              for (final template in BuiltInBots.all())
                DropdownMenuItem(
                  value: template.id,
                  child: Text(template.name),
                ),
            ],
            onChanged: (id) => setState(() {
              final previousName = _templateId == null
                  ? ''
                  : BuiltInBots.byId(_templateId!)!.name;
              _templateId = id;
              if (_name.text.trim().isEmpty || _name.text == previousName) {
                _name.text = id == null ? '' : BuiltInBots.byId(id)!.name;
              }
            }),
          ),
          if (_templateId != null) ...[
            const SizedBox(height: 8),
            Text(BuiltInBots.byId(_templateId!)!.description),
          ],
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: _portrait == null
                ? const DefaultBotAvatar(size: 48)
                : PetdexAvatar(
                    pet: _portrait!,
                    fallback: const DefaultBotAvatar(size: 48),
                  ),
            title: Text(t.profileImages.title),
            trailing: OutlinedButton(
              onPressed: _choose,
              child: Text(t.profileImages.choose),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(hintText: t.botCreation.name),
            onSubmitted: (_) => _submit(),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(t.common.cancel),
      ),
      FilledButton(
        onPressed: _name.text.trim().isEmpty ? null : _submit,
        child: Text(t.botCreation.create),
      ),
    ],
  );
}
