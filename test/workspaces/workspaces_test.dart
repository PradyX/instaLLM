import 'package:flutter_test/flutter_test.dart';
import 'package:installm/features/vault/data/vault_store.dart';
import 'package:installm/features/workspaces/domain/workspace.dart';

void main() {
  group('Workspace', () {
    test('round-trips the repository path and vault link', () {
      final workspace = Workspace.create(name: 'P').copyWith(
        vaultId: 'v1',
        vaultProjectPath: 'Projects/p',
        repositoryPath: '/home/user/code/p',
      );
      final restored = Workspace.fromJson(workspace.toJson())!;
      expect(restored.repositoryPath, '/home/user/code/p');
      expect(restored.vaultId, 'v1');
      expect(restored.vaultProjectPath, 'Projects/p');
      // Older files without the new fields still load.
      final legacy = Workspace.fromJson(const {'id': 'w', 'name': 'W'})!;
      expect(legacy.repositoryPath, isNull);
      expect(legacy.vaultProjectPath, isEmpty);
    });

    test('keeps the vault link of a workspace written before the rename', () {
      // Stored files named the link obsidianVaultId/obsidianProjectPath until
      // 2026-10-14. Reading them must not orphan an existing link, and what is
      // written back uses the new names only.
      final legacy = Workspace.fromJson(const {
        'id': 'w',
        'name': 'W',
        'obsidianVaultId': 'v1',
        'obsidianProjectPath': 'Projects/p',
      })!;
      expect(legacy.vaultId, 'v1');
      expect(legacy.vaultProjectPath, 'Projects/p');
      final rewritten = legacy.toJson();
      expect(rewritten['vaultId'], 'v1');
      expect(rewritten.containsKey('obsidianVaultId'), isFalse);

      // A newer name always wins over a stale legacy one in the same file.
      final both = Workspace.fromJson(const {
        'id': 'w',
        'name': 'W',
        'vaultId': 'new',
        'obsidianVaultId': 'old',
      })!;
      expect(both.vaultId, 'new');
    });

    test('bots only see assigned workspaces through allowsBot', () {
      final workspace = Workspace.create(
        name: 'P',
      ).copyWith(botIds: const ['coder']);
      expect(workspace.allowsBot('coder'), isTrue);
      expect(workspace.allowsBot('planner'), isFalse);
    });
  });

  group('WorkspaceVaultBinding', () {
    test('round-trips permissions with the defaults intact', () {
      const binding = WorkspaceVaultBinding(
        workspaceId: 'w',
        vaultId: 'v',
        projectPath: 'Projects/p',
      );
      final restored = WorkspaceVaultBinding.fromJson(binding.toJson())!;
      expect(restored.projectPath, 'Projects/p');
      expect(restored.permissions.canDelete, isFalse);
      expect(
        WorkspaceVaultBinding.fromJson(const {'workspaceId': 'w'}),
        isNull,
      );
    });
  });
}
