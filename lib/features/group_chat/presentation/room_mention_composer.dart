import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:installm/core/widgets/chat_composer.dart';
import 'package:installm/features/bots/domain/bot.dart';
import 'package:installm/features/profile_images/domain/petdex_pet.dart';
import 'package:installm/features/profile_images/presentation/profile_avatar.dart';
import 'package:installm/i18n/strings.g.dart';

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

class RoomMentionComposer extends StatefulWidget {
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

  @override
  State<RoomMentionComposer> createState() => _RoomMentionComposerState();
}

class _RoomMentionComposerState extends State<RoomMentionComposer> {
  final _focus = FocusNode();
  final _scroll = ScrollController();
  TextEditingValue? _dismissed;
  var _selected = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(RoomMentionComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _changed() => setState(() => _selected = 0);

  BotMentionQuery? get _query =>
      !widget.enabled || widget.controller.value == _dismissed
      ? null
      : BotMentionQuery.atCaret(widget.controller.value, widget.members);

  void _choose(BotMentionQuery query, Bot bot) {
    final next = query.insert(widget.controller.value, bot);
    _dismissed = next;
    widget.controller.value = next;
    _focus.requestFocus();
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    final query = _query;
    if (query == null ||
        event is KeyUpEvent ||
        HardwareKeyboard.instance.isShiftPressed ||
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      setState(() => _dismissed = widget.controller.value);
    } else if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowUp) {
      setState(
        () => _selected =
            (_selected + (key == LogicalKeyboardKey.arrowDown ? 1 : -1)) %
            query.matches.length,
      );
      if (_scroll.hasClients) {
        _scroll.jumpTo(
          (_selected * 56.0).clamp(0, _scroll.position.maxScrollExtent),
        );
      }
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.tab) {
      _choose(
        query,
        query.matches[_selected.clamp(0, query.matches.length - 1)],
      );
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final query = _query;
    return ChatComposer(
      controller: widget.controller,
      enabled: widget.enabled,
      hintText: widget.hintText,
      onSend: widget.onSend,
      focusNode: _focus,
      onKeyEvent: _key,
      leading: widget.leading,
      reasoning: widget.reasoning,
      onMicPressed: widget.onMicPressed,
      micState: widget.micState,
      header: query == null
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.roomMentions.title,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 180),
                  child: ListView.builder(
                    controller: _scroll,
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: query.matches.length,
                    itemBuilder: (context, index) {
                      final bot = query.matches[index];
                      return Material(
                        type: MaterialType.transparency,
                        child: ListTile(
                          key: ValueKey('mention-${bot.id}'),
                          dense: true,
                          selected: index == _selected,
                          selectedTileColor: Theme.of(
                            context,
                          ).colorScheme.primaryContainer,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          leading: ProfileAvatar(
                            profileKey: botProfileKey(bot.id),
                          ),
                          title: Text(
                            '@${bot.name}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => _choose(query, bot),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
