import 'package:installm/features/memory/application/memory_controller.dart';
import 'package:installm/features/memory/domain/memory_command.dart';
import 'package:installm/features/memory/domain/memory_fact.dart';
import 'package:installm/i18n/strings.g.dart';

Future<String> applyMemoryCommand(
  MemoryNotifier memory,
  MemoryCommand command, {
  required String conversationId,
  String? workspaceId,
}) async {
  if (command.scope == MemoryScope.workspace && workspaceId == null) {
    return t.memory.workspaceRequired;
  }
  final owner = switch (command.scope) {
    MemoryScope.conversation => conversationId,
    MemoryScope.workspace => workspaceId,
    MemoryScope.global => null,
  };
  if (command.forget) {
    return memory.forgetText(
      text: command.text,
      scope: command.scope,
      ownerId: owner,
    );
  }
  final fact = await memory.remember(
    text: command.text,
    scope: command.scope,
    ownerId: owner,
    // This flag can only come from the user's explicit "globally:" command.
    globalOptIn: command.scope == MemoryScope.global,
  );
  return fact == null
      ? memory.errorMessage ?? t.memory.saveError
      : '${t.memory.remembered} (${switch (command.scope) {
          MemoryScope.conversation => t.memory.conversation,
          MemoryScope.workspace => t.memory.workspace,
          MemoryScope.global => t.memory.global,
        }})';
}
