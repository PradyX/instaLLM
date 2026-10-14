import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:installm/features/conversations/presentation/conversation_controller.dart';
import 'package:installm/features/group_chat/application/active_room.dart';
import 'package:installm/features/group_chat/application/group_chat_controller.dart';
import 'package:installm/features/memory/application/memory_controller.dart';
import 'package:installm/features/memory/domain/memory_fact.dart';
import 'package:installm/features/workspaces/application/workspaces_controller.dart';
import 'package:installm/features/kanban/application/kanban_controller.dart'
    show activeWorkspaceIdProvider;
import 'package:installm/i18n/strings.g.dart';

String memoryScopeLabel(MemoryScope scope) => switch (scope) {
  MemoryScope.conversation => t.memory.conversation,
  MemoryScope.workspace => t.memory.workspace,
  MemoryScope.global => t.memory.global,
};

String memorySourceLabel(MemorySource source) => switch (source) {
  MemorySource.userStated => t.memory.userStated,
  MemorySource.inferred => t.memory.inferred,
  MemorySource.botRecorded => t.memory.botRecorded,
};

Map<String, String> _owners(WidgetRef ref, MemoryScope scope) =>
    switch (scope) {
      MemoryScope.conversation => {
        for (final item in ref.watch(conversationControllerProvider).summaries)
          item.conversation.id: item.conversation.title,
        for (final room in ref.watch(groupChatsProvider).snapshot.chats)
          room.id: room.name,
      },
      MemoryScope.workspace => {
        for (final workspace in ref.watch(workspacesProvider).workspaces)
          workspace.id: workspace.name,
      },
      MemoryScope.global => {},
    };

class MemoryPage extends ConsumerWidget {
  const MemoryPage({super.key});

  Future<void> _editor(BuildContext context, MemoryFact? fact) =>
      showDialog<void>(
        context: context,
        builder: (_) => _FactEditor(fact: fact),
      );

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    MemoryFact fact,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.memory.deleteTitle),
        content: Text(t.memory.deleteHint),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.common.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(t.memory.delete),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await ref.read(memoryProvider.notifier).forget(fact.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memory = ref.watch(memoryProvider);
    final conversationOwners = _owners(ref, MemoryScope.conversation);
    final workspaceOwners = _owners(ref, MemoryScope.workspace);
    final editable = memory.isReady && !memory.isReadOnly;
    final facts = [...memory.facts]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return Scaffold(
      appBar: AppBar(
        title: Text(t.memory.title),
        actions: [
          IconButton(
            tooltip: t.memory.add,
            icon: const Icon(Icons.add),
            onPressed: editable ? () => _editor(context, null) : null,
          ),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                t.memory.subtitle,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(t.memory.commands),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(t.memory.help),
                  ),
                ],
              ),
              if (memory.errorMessage != null) ...[
                Text(
                  memory.errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => ref.invalidate(memoryProvider),
                    child: Text(t.memory.retry),
                  ),
                ),
              ],
              if (!memory.isReady)
                const Center(child: CircularProgressIndicator())
              else if (facts.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(t.memory.empty),
                ),
              for (final fact in facts) ...[
                ListTile(
                  key: ValueKey('fact-${fact.id}'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(fact.text),
                  subtitle: Text(
                    [
                      memoryScopeLabel(fact.scope),
                      if (fact.ownerId != null)
                        (fact.scope == MemoryScope.workspace
                                ? workspaceOwners
                                : conversationOwners)[fact.ownerId] ??
                            t.memory.unavailableOwner,
                      memorySourceLabel(fact.source),
                      if (fact.isExpired(DateTime.now())) t.memory.expired,
                      if (fact.scope == MemoryScope.global && !fact.globalOptIn)
                        t.memory.globalDisabled,
                      if (fact.expiresAt != null)
                        DateFormat.yMMMd().format(fact.expiresAt!.toLocal()),
                    ].join(' · '),
                  ),
                  trailing: PopupMenuButton<String>(
                    enabled: editable,
                    tooltip: t.memory.actions,
                    onSelected: (action) {
                      if (action == 'edit') _editor(context, fact);
                      if (action == 'delete') _delete(context, ref, fact);
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(value: 'edit', child: Text(t.memory.edit)),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text(
                          t.memory.delete,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FactEditor extends ConsumerStatefulWidget {
  const _FactEditor({this.fact});
  final MemoryFact? fact;
  @override
  ConsumerState<_FactEditor> createState() => _FactEditorState();
}

class _FactEditorState extends ConsumerState<_FactEditor> {
  late final TextEditingController _text;
  late final TextEditingController _expiry;
  late MemoryScope _scope;
  String? _ownerId;
  late bool _globalOptIn;
  bool _saving = false;
  String? _error;

  String _date(DateTime value) =>
      DateFormat('yyyy-MM-dd').format(value.toLocal());

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: widget.fact?.text ?? '');
    _expiry = TextEditingController(
      text: widget.fact?.expiresAt == null
          ? ''
          : _date(widget.fact!.expiresAt!),
    );
    _scope = widget.fact?.scope ?? MemoryScope.conversation;
    _ownerId = widget.fact?.ownerId;
    _globalOptIn = widget.fact?.globalOptIn ?? false;
  }

  @override
  void dispose() {
    _text.dispose();
    _expiry.dispose();
    super.dispose();
  }

  Future<void> _save(String? owner) async {
    if (_saving) return;
    final text = _text.text.trim();
    var error = text.isEmpty || text.length > MemoryFact.maxTextCharacters
        ? t.memory.textError
        : null;
    DateTime? expiry;
    final dateText = _expiry.text.trim();
    if (dateText.isNotEmpty) {
      expiry = DateTime.tryParse(dateText);
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(dateText) ||
          expiry == null ||
          _date(expiry) != dateText) {
        error = t.memory.dateError;
      } else if (widget.fact?.expiresAt != null &&
          dateText == _date(widget.fact!.expiresAt!)) {
        expiry = widget.fact!.expiresAt;
      }
    }
    if (_scope != MemoryScope.global && owner == null) {
      error = t.memory.ownerError;
    }
    if (widget.fact == null && _scope == MemoryScope.global && !_globalOptIn) {
      error = t.memory.globalRequired;
    }
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final memory = ref.read(memoryProvider.notifier);
    final saved = widget.fact == null
        ? await memory.remember(
                text: text,
                scope: _scope,
                ownerId: owner,
                expiresAt: expiry,
                globalOptIn: _globalOptIn,
              ) !=
              null
        : await memory.edit(
            widget.fact!.id,
            text: text,
            expiresAt: expiry,
            clearExpiry: dateText.isEmpty,
            globalOptIn: _globalOptIn,
          );
    if (!mounted) return;
    if (saved) {
      Navigator.pop(context);
    } else {
      setState(() {
        _saving = false;
        _error = memory.errorMessage ?? t.memory.saveError;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final owners = _owners(ref, _scope);
    final activeOwner = _scope == MemoryScope.workspace
        ? ref.watch(activeWorkspaceIdProvider)
        : ref.watch(activeRoomIdProvider) ??
              ref.watch(conversationControllerProvider).activeConversationId;
    final owner = _scope == MemoryScope.global
        ? null
        : _ownerId ?? (owners.containsKey(activeOwner) ? activeOwner : null);
    final editing = widget.fact != null;
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: Text(editing ? t.memory.edit : t.memory.add),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  key: const ValueKey('memory-text'),
                  controller: _text,
                  minLines: 2,
                  maxLines: 5,
                  enabled: !_saving,
                  maxLength: MemoryFact.maxTextCharacters,
                  decoration: InputDecoration(labelText: t.memory.fact),
                ),
                if (editing)
                  Text(
                    '${memoryScopeLabel(_scope)} · ${memorySourceLabel(widget.fact!.source)}',
                  )
                else ...[
                  DropdownButtonFormField<MemoryScope>(
                    key: ValueKey('memory-scope-$_scope'),
                    initialValue: _scope,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: t.memory.scope),
                    items: [
                      for (final scope in MemoryScope.values)
                        DropdownMenuItem(
                          value: scope,
                          child: Text(memoryScopeLabel(scope)),
                        ),
                    ],
                    onChanged: _saving
                        ? null
                        : (scope) {
                            if (scope != null) {
                              setState(() {
                                _scope = scope;
                                _ownerId = null;
                                _globalOptIn = false;
                              });
                            }
                          },
                  ),
                  if (_scope != MemoryScope.global) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      key: ValueKey('memory-owner-$owner'),
                      initialValue: owner,
                      isExpanded: true,
                      decoration: InputDecoration(labelText: t.memory.owner),
                      items: [
                        for (final entry in owners.entries)
                          DropdownMenuItem(
                            value: entry.key,
                            child: Text(
                              entry.value,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: _saving
                          ? null
                          : (id) => setState(() => _ownerId = id),
                    ),
                  ],
                ],
                if (_scope == MemoryScope.global) ...[
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(t.memory.globalConsent),
                    value: _globalOptIn,
                    onChanged: _saving
                        ? null
                        : (value) =>
                              setState(() => _globalOptIn = value ?? false),
                  ),
                  Text(
                    t.memory.globalHint,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('memory-expiry'),
                  controller: _expiry,
                  enabled: !_saving,
                  decoration: InputDecoration(labelText: t.memory.expires),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: Text(t.common.cancel),
          ),
          FilledButton(
            onPressed: _saving ? null : () => _save(owner),
            child: Text(t.memory.save),
          ),
        ],
      ),
    );
  }
}
