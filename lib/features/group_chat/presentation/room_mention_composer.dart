import 'package:flutter/material.dart';
import 'package:installm/core/widgets/chat_composer.dart';
import 'package:installm/core/widgets/composer_command_picker.dart';
import 'package:installm/features/bots/domain/bot.dart';
import 'package:installm/features/profile_images/domain/petdex_pet.dart';
import 'package:installm/features/profile_images/presentation/profile_avatar.dart';

/// The mention being edited at the caret, with room-member prefix matches.
class BotMentionQuery {
  const BotMentionQuery(this.start, this.cursor, this.matches);
  final int start;
  final int cursor;
  final List<Bot> matches;

  static BotMentionQuery? atCaret(TextEditingValue value, List<Bot> members) {
    if (!value.selection.isValid ||
        !value.selection.isCollapsed ||
        !value.composing.isCollapsed) {
      return null;
    }
    final cursor = value.selection.baseOffset;
    if (cursor > value.text.length) return null;
    final prefix = value.text.substring(0, cursor);
    final start = prefix.lastIndexOf('@');
    if (start < 0 ||
        (start > 0 && !RegExp(r'[\s(\[{]').hasMatch(prefix[start - 1]))) {
      return null;
    }
    final query = prefix.substring(start + 1).toLowerCase();
    if (query.contains('\n')) return null;
    final matches = members
        .where((bot) => bot.name.toLowerCase().startsWith(query))
        .toList();
    return matches.isEmpty ? null : BotMentionQuery(start, cursor, matches);
  }

  TextEditingValue insert(TextEditingValue value, Bot bot) {
    // Replace the whole partial handle when editing in the middle of it.
    var end = cursor;
    final fullName = '@${bot.name}';
    if (value.text
        .substring(start)
        .toLowerCase()
        .startsWith(fullName.toLowerCase())) {
      end = start + fullName.length;
    } else {
      while (end < value.text.length &&
          !RegExp(r'[\s.,!?;:)\]}@]').hasMatch(value.text[end])) {
        end++;
      }
    }
    final suffix = value.text.substring(end);
    final separator =
        suffix.isNotEmpty && RegExp(r'[\s.,!?;:)\]}]').hasMatch(suffix[0])
        ? ''
        : ' ';
    final handle = '$fullName$separator';
    return TextEditingValue(
      text: value.text.replaceRange(start, end, handle),
      selection: TextSelection.collapsed(offset: start + handle.length),
    );
  }
}

class RoomMentionComposer extends StatelessWidget {
  const RoomMentionComposer({
    super.key,
    required this.controller,
    required this.members,
    required this.enabled,
    required this.hintText,
    required this.onSend,
    this.leading,
    this.reasoning,
    this.onMicPressed,
    this.micState = ComposerMicState.idle,
    this.commands = const [],
  });
  final TextEditingController controller;
  final List<Bot> members;
  final bool enabled;
  final String hintText;
  final Future<void> Function() onSend;
  final Widget? leading;
  final Widget? reasoning;
  final VoidCallback? onMicPressed;
  final ComposerMicState micState;
  final List<ComposerCommand> commands;

  @override
  Widget build(BuildContext context) => ChatComposer(
    commands: commands,
    controller: controller,
    enabled: enabled,
    hintText: hintText,
    onSend: onSend,
    leading: leading,
    reasoning: reasoning,
    onMicPressed: onMicPressed,
    micState: micState,
    additionalQuery: (value) {
      final query = BotMentionQuery.atCaret(value, members);
      if (query == null) return null;
      Bot botFor(ComposerCommand option) =>
          query.matches.firstWhere((bot) => '@${bot.name}' == option.command);
      return ComposerCommandQuery(
        query.start,
        query.cursor,
        [
          for (final bot in query.matches)
            (command: '@${bot.name}', description: bot.description),
        ],
        insertValue: (value, option) => query.insert(value, botFor(option)),
        leading: (option) =>
            ProfileAvatar(profileKey: botProfileKey(botFor(option).id)),
      );
    },
  );
}
