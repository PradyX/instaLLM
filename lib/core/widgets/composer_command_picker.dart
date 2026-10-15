import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

typedef ComposerCommand = ({String command, String description});

/// Only the initial slash token is completed; an existing task is preserved.
class ComposerCommandQuery {
  const ComposerCommandQuery(
    this.start,
    this.end,
    this.matches, {
    this.insertValue,
    this.leading,
  });
  final int start;
  final int end;
  final List<ComposerCommand> matches;
  final TextEditingValue Function(TextEditingValue, ComposerCommand)?
  insertValue;
  final Widget Function(ComposerCommand)? leading;

  static ComposerCommandQuery? atCaret(
    TextEditingValue value,
    List<ComposerCommand> commands,
  ) {
    if (!value.selection.isValid ||
        !value.selection.isCollapsed ||
        !value.composing.isCollapsed) {
      return null;
    }
    final token = RegExp(r'^\s*/[^\s]*').firstMatch(value.text);
    if (token == null) return null;
    final start = value.text.indexOf('/');
    final cursor = value.selection.baseOffset;
    if (cursor <= start || cursor > token.end) return null;
    final prefix = value.text.substring(start, cursor).toLowerCase();
    final matches = commands
        .where((option) => option.command.toLowerCase().startsWith(prefix))
        .toList();
    return matches.isEmpty
        ? null
        : ComposerCommandQuery(start, token.end, matches);
  }

  TextEditingValue insert(TextEditingValue value, ComposerCommand option) {
    if (insertValue != null) return insertValue!(value, option);
    final suffix = value.text.substring(end);
    final command = '${option.command}${suffix.isEmpty ? ' ' : ''}';
    return TextEditingValue(
      text: value.text.replaceRange(start, end, command),
      selection: TextSelection.collapsed(offset: start + command.length),
    );
  }
}

/// Anchors a bounded command list above the composer without resizing history.
class ComposerCommandPicker extends StatefulWidget {
  const ComposerCommandPicker({
    super.key,
    required this.controller,
    required this.enabled,
    required this.commands,
    required this.onSend,
    required this.builder,
    this.focusNode,
    this.onKeyEvent,
    this.additionalQuery,
  });
  final TextEditingController controller;
  final bool enabled;
  final List<ComposerCommand> commands;
  final Future<void> Function() onSend;
  final FocusNode? focusNode;
  final KeyEventResult Function(FocusNode, KeyEvent)? onKeyEvent;
  final ComposerCommandQuery? Function(TextEditingValue)? additionalQuery;
  final Widget Function(
    FocusNode focus,
    KeyEventResult Function(FocusNode, KeyEvent) onKey,
    Future<void> Function() submit,
  )
  builder;

  @override
  State<ComposerCommandPicker> createState() => _ComposerCommandPickerState();
}

class _ComposerCommandPickerState extends State<ComposerCommandPicker> {
  final _ownedFocus = FocusNode();
  final _portal = OverlayPortalController();
  final _link = LayerLink();
  final _anchor = GlobalKey();
  final _scroll = ScrollController();
  final _selectedRow = GlobalKey();
  TextEditingValue? _dismissed;
  int _selected = 0;
  FocusNode get _focus => widget.focusNode ?? _ownedFocus;
  ComposerCommandQuery? get _query =>
      widget.enabled && _focus.hasFocus && widget.controller.value != _dismissed
      ? ComposerCommandQuery.atCaret(
              widget.controller.value,
              widget.commands,
            ) ??
            widget.additionalQuery?.call(widget.controller.value)
      : null;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    _focus.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncOverlay());
  }

  @override
  void didUpdateWidget(ComposerCommandPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
      _dismissed = null;
    }
    if (oldWidget.focusNode != widget.focusNode) {
      (oldWidget.focusNode ?? _ownedFocus).removeListener(_changed);
      _focus.addListener(_changed);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncOverlay());
  }

  void _syncOverlay() {
    if (!mounted) return;
    if (_query != null) {
      if (!_portal.isShowing) _portal.show();
    } else if (_portal.isShowing) {
      _portal.hide();
    }
  }

  void _changed() {
    if (widget.controller.value != _dismissed) _dismissed = null;
    setState(() => _selected = 0);
    _syncOverlay();
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _choose(ComposerCommandQuery query, ComposerCommand option) {
    final next = query.insert(widget.controller.value, option);
    _dismissed = next;
    widget.controller.value = next;
    _focus.requestFocus();
  }

  Future<void> _submit() async {
    final query = _query;
    if (query != null) {
      _choose(
        query,
        query.matches[_selected.clamp(0, query.matches.length - 1)],
      );
    } else {
      await widget.onSend();
    }
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    final query = _query;
    if (query == null ||
        event is KeyUpEvent ||
        HardwareKeyboard.instance.isShiftPressed ||
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.isMetaPressed) {
      return widget.onKeyEvent?.call(node, event) ?? KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      _dismissed = widget.controller.value;
      _syncOverlay();
    } else if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _selected =
            (_selected + (key == LogicalKeyboardKey.arrowDown ? 1 : -1)) %
            query.matches.length;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final row = _selectedRow.currentContext;
        if (mounted && row != null) {
          Scrollable.ensureVisible(row, alignment: 0.5);
        }
      });
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.tab) {
      _choose(
        query,
        query.matches[_selected.clamp(0, query.matches.length - 1)],
      );
    } else {
      return widget.onKeyEvent?.call(node, event) ?? KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  Widget _overlay(BuildContext context) {
    final query = _query;
    final box = _anchor.currentContext?.findRenderObject() as RenderBox?;
    if (query == null || box == null || !box.hasSize) {
      return const SizedBox.shrink();
    }
    final media = MediaQuery.of(context);
    final height = math.min(
      280.0,
      box.localToGlobal(Offset.zero).dy - media.padding.top - 8,
    );
    if (height < 48) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    final selected = _selected.clamp(0, query.matches.length - 1);
    return CompositedTransformFollower(
      link: _link,
      showWhenUnlinked: false,
      targetAnchor: Alignment.topLeft,
      followerAnchor: Alignment.bottomLeft,
      offset: const Offset(0, -8),
      child: Align(
        alignment: Alignment.bottomLeft,
        widthFactor: 1,
        heightFactor: 1,
        child: SizedBox(
          width: math.min(440, box.size.width),
          child: TextFieldTapRegion(
            child: Material(
              color: colors.surfaceContainerHigh,
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: colors.outlineVariant),
              ),
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: height),
                child: Scrollbar(
                  controller: _scroll,
                  child: SingleChildScrollView(
                    controller: _scroll,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < query.matches.length; i++)
                          ListTile(
                            key: i == selected ? _selectedRow : null,
                            dense: true,
                            selected: i == selected,
                            selectedTileColor: colors.primaryContainer,
                            leading: query.leading?.call(query.matches[i]),
                            title: Text(query.matches[i].command),
                            subtitle: query.matches[i].description.isEmpty
                                ? null
                                : Text(query.matches[i].description),
                            onTap: () => _choose(query, query.matches[i]),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => OverlayPortal(
    controller: _portal,
    overlayChildBuilder: _overlay,
    child: CompositedTransformTarget(
      key: _anchor,
      link: _link,
      child: widget.builder(_focus, _key, _submit),
    ),
  );

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _focus.removeListener(_changed);
    _ownedFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }
}
