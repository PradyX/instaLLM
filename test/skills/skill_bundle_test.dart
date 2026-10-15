import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:installm/core/permissions/workspace_permission.dart';
import 'package:installm/features/skills/data/skill_bundle_service.dart';
import 'package:installm/features/skills/data/skill_store.dart';
import 'package:installm/features/skills/domain/built_in_skills.dart';
import 'package:installm/features/skills/domain/skill.dart';
import 'package:installm/features/skills/domain/skill_selector.dart';
import 'package:installm/features/skills/application/skill_session.dart';

void main() {
  late Directory root;
  File write(String name, String text) {
    final file = File('${root.path}/$name');
    file.parent.createSync(recursive: true);
    return file..writeAsStringSync(text);
  }

  List<dynamic> loadDisabledIds(File file) =>
      (jsonDecode(file.readAsStringSync())
              as Map<String, dynamic>)['disabledBuiltInIds']
          as List<dynamic>;

  setUp(() => root = Directory.systemTemp.createTempSync('skill-bundle-'));
  tearDown(() => root.deleteSync(recursive: true));

  test(
    'explicit import copies only declared text and survives source removal',
    () async {
      final manifest = write(
        'SKILL.md',
        '---\nname: docs\nresources:\n  - references/guide.md\nscripts:\n  - scripts/check.sh\n---\nWrite docs.',
      );
      write('references/guide.md', 'Use simple words.');
      write('scripts/check.sh', 'printf ok');
      write('references/private.md', 'Never imported');
      final skill = await const SkillBundleService().importFile(manifest);
      expect(skill.bundleFiles.keys, [
        'references/guide.md',
        'scripts/check.sh',
      ]);
      File('${root.path}/references/guide.md').deleteSync();
      final store = SkillStore(File('${root.path}/registry.json'));
      expect(store.save(SkillsSnapshot(customSkills: [skill])), isTrue);
      final restored = store.load().customSkills.single;
      final session = SkillSession(
        skills: [restored],
        tokenBudget: 500,
        isCurrent: (_) => true,
      );
      expect(session.resourceTokens, 0);
      expect(
        session.readResource(skill.id, 'references/guide.md'),
        contains('Use simple words.'),
      );
      expect(session.resourceTokens, greaterThan(0));
      expect(
        session.readResource(skill.id, 'references/guide.md'),
        contains('already loaded'),
      );
      expect(
        session.readResource(skill.id, 'references/private.md'),
        contains('unavailable'),
      );
    },
  );
  test(
    'missing, binary, oversized, traversal and linked files refuse import',
    () async {
      for (final path in [
        '../private.md',
        '/tmp/private.md',
        'references/../private.md',
        'references/missing.md',
      ]) {
        final manifest = write(
          'SKILL.md',
          '---\nresources:\n  - $path\n---\nRead docs.',
        );
        await expectLater(
          const SkillBundleService().importFile(manifest),
          throwsFormatException,
        );
      }
      final manifest = write(
        'SKILL.md',
        '---\nresources:\n  - references/a.md\n---\nRead docs.',
      );
      write('references/a.md', '\u0000binary');
      await expectLater(
        const SkillBundleService().importFile(manifest),
        throwsFormatException,
      );
      write('references/a.md', 'a' * (SkillBundleService.maxFileBytes + 1));
      await expectLater(
        const SkillBundleService().importFile(manifest),
        throwsFormatException,
      );
      File('${root.path}/references/a.md').deleteSync();
      final other = write('other.md', 'Private');
      Link('${root.path}/references/a.md').createSync(other.path);
      await expectLater(
        const SkillBundleService().importFile(manifest),
        throwsFormatException,
      );
    },
  );
  test(
    'v1/partial/corrupt originals are preserved and future schemas refuse writes',
    () {
      final skill = Skill.create(name: 'Old instructions', body: 'Keep me');
      final file = write(
        'registry.json',
        jsonEncode({
          'version': 1,
          'skills': [
            skill.toJson(),
            {'broken': true},
            42,
          ],
          'unknown': true,
        }),
      );
      final original = file.readAsStringSync();
      final store = SkillStore(file);
      expect(store.save(store.load()), isTrue);
      expect(
        jsonDecode(file.readAsStringSync())['version'],
        SkillStore.currentVersion,
      );
      expect(store.load().customSkills.single.body, 'Keep me');
      expect(
        root
            .listSync()
            .whereType<File>()
            .where((f) => f.path.contains('preserved'))
            .single
            .readAsStringSync(),
        original,
      );
      file.writeAsStringSync('corrupt');
      expect(store.save(store.load()), isTrue);
      expect(
        root
            .listSync()
            .whereType<File>()
            .where((f) => f.path.contains('preserved'))
            .length,
        2,
      );
      file.writeAsStringSync('{"version":99,"skills":[]}');
      expect(store.save(SkillsSnapshot.empty), isFalse);
      expect(file.readAsStringSync(), '{"version":99,"skills":[]}');
    },
  );
  test('a v2 registry keeps its custom skills and disables when rewritten', () {
    final skill = Skill.create(name: 'Old instructions', body: 'Keep me');
    final builtIn = BuiltInSkills.all().first;
    final file = write(
      'registry.json',
      jsonEncode({
        'version': 2,
        'skills': [
          skill.toJson(),
          {'source': 'builtIn', 'id': builtIn.id},
        ],
        'disabledBuiltInIds': [builtIn.id],
      }),
    );
    final store = SkillStore(file);
    final loaded = store.load();
    expect(loaded.customSkills.single.body, 'Keep me');
    expect(loaded.removedBuiltInIds, isEmpty);
    expect(
      loaded.allSkills
          .where((candidate) => candidate.id == builtIn.id)
          .single
          .enabled,
      isFalse,
    );
    expect(store.save(loaded), isTrue);
    final rewritten =
        jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    expect(rewritten['version'], SkillStore.currentVersion);
    expect(rewritten['disabledBuiltInIds'], [builtIn.id]);
    expect(rewritten['removedBuiltInIds'], isEmpty);
    // The v2 file is kept as a backup before the rewrite.
    expect(
      root
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('preserved'))
          .length,
      1,
    );
  });
  test('a removed built-in is dropped from the list and offered back', () {
    final builtIn = BuiltInSkills.all().first;
    final file = File('${root.path}/registry.json');
    final store = SkillStore(file);
    expect(store.save(SkillsSnapshot.empty.removeBuiltIn(builtIn.id)), isTrue);

    final reloaded = store.load();
    expect(reloaded.allSkills.any((skill) => skill.id == builtIn.id), isFalse);
    expect(reloaded.removedBuiltInSkills.single.id, builtIn.id);
    expect(
      loadDisabledIds(file),
      isEmpty,
      reason: 'a skill that is not listed keeps no switch state',
    );

    expect(store.save(reloaded.restoreBuiltIn(builtIn.id)), isTrue);
    final restored = store.load();
    expect(restored.removedBuiltInSkills, isEmpty);
    expect(restored.allSkills.first.id, builtIn.id);
    expect(restored.allSkills.first.enabled, isTrue);
  });
  test(
    'resource budgets and revoked eligibility refuse text without consuming budget',
    () {
      final skill = Skill.create(
        name: 'docs',
        body: 'Read',
        resourceNames: ['references/a.md'],
        bundleFiles: {'references/a.md': 'x' * 2000},
      );
      var current = true;
      final session = SkillSession(
        skills: [skill],
        tokenBudget: 100,
        isCurrent: (_) => current,
      );
      expect(
        session.readResource(skill.id, 'references/a.md'),
        contains('budget'),
      );
      expect(session.resourceTokens, 0);
      current = false;
      expect(
        session.readResource(skill.id, 'references/a.md'),
        contains('unavailable'),
      );
      expect(
        session.readResource('other', 'references/a.md'),
        contains('unavailable'),
      );
    },
  );
  test(
    'workspace and capability boundaries hold even with no active workspace',
    () {
      final skill = Skill.create(
        name: 'docs',
        workspaceId: 'w',
        requiredCapabilities: {'filesystem:read'},
      );
      List<Skill> rank(String? workspace, Set<Capability> capabilities) =>
          SkillSelector.rank(
            skills: [skill],
            taskText: 'docs',
            workspaceId: workspace,
            botCapabilities: capabilities,
          );
      expect(rank(null, {const Capability('filesystem:read')}), isEmpty);
      expect(rank('other', {const Capability('filesystem:read')}), isEmpty);
      expect(rank('w', {}), isEmpty);
      expect(rank('w', {const Capability('filesystem:read')}), [skill]);
    },
  );
}
