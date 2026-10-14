import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:installm/core/services/app_storage_service.dart';
import 'package:installm/features/vault/application/vaults_controller.dart';
import 'package:installm/features/vault/data/vault_store.dart';
import 'package:installm/features/vault/domain/vault_registration.dart';

void main() {
  late Directory root;
  late File file;
  setUp(() {
    root = Directory.systemTemp.createTempSync('installm-managed-');
    file = File('${root.path}/support/vaults.json');
  });
  tearDown(() => root.deleteSync(recursive: true));
  Future<ProviderContainer> container({bool mobile = false}) async {
    final scope = ProviderContainer(
      overrides: [
        vaultStoreProvider.overrideWith((ref) async => VaultStore(file)),
        vaultStorageProvider.overrideWithValue(
          AppStorageService(
            documentsDirectory: Directory('${root.path}/Documents'),
            mobile: mobile,
          ),
        ),
      ],
    );
    addTearDown(scope.dispose);
    await scope.read(vaultsProvider.notifier).whenReady;
    return scope;
  }

  test(
    'explicit managed registration is idempotent and retains external bindings',
    () async {
      final external = VaultRegistration.create(
        id: 'external',
        name: 'My notes',
        rootPath: '${root.path}/external',
      );
      VaultStore(file).save(
        VaultsSnapshot(
          vaults: [external],
          bindings: [
            const WorkspaceVaultBinding(
              workspaceId: 'w',
              vaultId: 'external',
              projectPath: 'Project',
            ),
          ],
        ),
      );
      final scope = await container();
      final notifier = scope.read(vaultsProvider.notifier);
      final first = await notifier.ensureManagedVault();
      expect(first?.isManaged, isTrue);
      expect(first?.rootPath, '${root.path}/Documents/InstaLLM/vault');
      expect((await notifier.ensureManagedVault())?.id, first?.id);
      expect(scope.read(vaultsProvider).vaults, hasLength(2));
      expect(
        scope.read(vaultsProvider).snapshot.bindingFor('w')?.vaultId,
        'external',
      );
      expect(
        VaultStore(file).load().vaults.where((v) => v.isManaged),
        hasLength(1),
      );
    },
  );

  test('concurrent registry changes retain both new registrations', () async {
    final scope = await container();
    final notifier = scope.read(vaultsProvider.notifier);
    await Future.wait([
      notifier.registerVault('One', '${root.path}/one'),
      notifier.registerVault('Two', '${root.path}/two'),
    ]);
    expect(VaultStore(file).load().vaults, hasLength(2));
    expect(scope.read(vaultsProvider).vaults, hasLength(2));
  });
  test(
    'mobile managed Vault uses private documents and future registries remain untouched',
    () async {
      final scope = await container(mobile: true);
      expect(
        (await scope.read(vaultsProvider.notifier).ensureManagedVault())
            ?.rootPath,
        '${root.path}/Documents/vault',
      );
      file.writeAsStringSync('{"version":99,"vaults":[]}');
      final newer = await container();
      expect(
        await newer.read(vaultsProvider.notifier).ensureManagedVault(),
        isNull,
      );
      expect(file.readAsStringSync(), '{"version":99,"vaults":[]}');
    },
  );

  test(
    'managed registry roots rebase on load without changing external links',
    () async {
      final managed = VaultRegistration.create(
        id: 'm',
        name: 'InstaLLM',
        rootPath: '/old/ios/sandbox/Documents/vault',
        isManaged: true,
      );
      final external = VaultRegistration.create(
        id: 'e',
        name: 'Notes',
        rootPath: '/user/notes',
      );
      VaultStore(file).save(VaultsSnapshot(vaults: [managed, external]));
      final scope = await container(mobile: true);
      expect(
        scope.read(vaultsProvider).snapshot.vaultById('m')?.rootPath,
        '${root.path}/Documents/vault',
      );
      expect(
        VaultStore(file).load().vaultById('e')?.rootPath,
        external.rootPath,
      );
    },
  );
  test(
    'v1 and partial/corrupt data are preserved; failed saves do not publish a registry change',
    () async {
      final external = VaultRegistration.create(
        name: 'Notes',
        rootPath: '${root.path}/notes',
      );
      file.parent.createSync(recursive: true);
      final original = jsonEncode({
        'version': 1,
        'vaults': [
          external.toJson(),
          {'partial': true},
        ],
        'bindings': [],
        'unknown': 42,
      });
      file.writeAsStringSync(original);
      final store = VaultStore(file);
      expect(store.save(store.load()), isTrue);
      expect(store.load().vaults.single.id, external.id);
      final preserved = file.parent
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('.preserved-'))
          .single;
      expect(preserved.readAsStringSync(), original);
      final scope = await container();
      final blocker = Directory('${file.path}.tmp')..createSync();
      final before = scope.read(vaultsProvider).snapshot;
      expect(
        await scope
            .read(vaultsProvider.notifier)
            .registerVault('Will fail', '${root.path}/fail'),
        isNull,
      );
      expect(scope.read(vaultsProvider).snapshot, same(before));
      blocker.deleteSync();
      file.writeAsStringSync('broken registry');
      expect(store.save(VaultsSnapshot.empty), isTrue);
      expect(
        file.parent.listSync().whereType<File>().any(
          (f) =>
              f.path.contains('.preserved-') &&
              f.readAsStringSync() == 'broken registry',
        ),
        isTrue,
      );
    },
  );
}
