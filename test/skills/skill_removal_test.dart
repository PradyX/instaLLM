import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:installm/features/skills/application/skills_controller.dart';
import 'package:installm/features/skills/data/skill_store.dart';
import 'package:installm/features/skills/domain/built_in_skills.dart';
import 'package:installm/features/skills/domain/skill.dart';
import 'package:installm/features/skills/presentation/skills_page.dart';

/// What the user can remove from Settings › Skills.
///
/// A built-in is code, so removing it only takes it out of the registry and
/// offers it back; an imported skill is deleted with its copied bundle, which
/// is why that one asks first.
void main() {
  late Directory root;
  late File registry;
  late ProviderContainer container;

  setUp(() {
    root = Directory.systemTemp.createTempSync('skill-removal-');
    registry = File('${root.path}/skills.json');
    container = ProviderContainer(
      overrides: [
        skillStoreProvider.overrideWith((ref) => SkillStore(registry)),
      ],
    );
    addTearDown(container.dispose);
  });
  tearDown(() => root.deleteSync(recursive: true));

  test('removing a built-in unlists it and keeps it restorable', () async {
    final notifier = container.read(skillsProvider.notifier);
    await notifier.whenReady;
    final builtIn = BuiltInSkills.all().first;
    expect(container.read(skillsProvider).skillById(builtIn.id), isNotNull);

    expect(await notifier.removeSkill(builtIn.id), isTrue);

    final state = container.read(skillsProvider);
    expect(state.skillById(builtIn.id), isNull);
    expect(state.builtInSkills.length, BuiltInSkills.all().length - 1);
    expect(state.removedBuiltInSkills.single.id, builtIn.id);
    expect(jsonDecode(registry.readAsStringSync())['removedBuiltInIds'], [
      builtIn.id,
    ]);

    // A second read of the same file (a restart) still knows it was removed.
    final reloaded = ProviderContainer(
      overrides: [
        skillStoreProvider.overrideWith((ref) => SkillStore(registry)),
      ],
    );
    addTearDown(reloaded.dispose);
    await reloaded.read(skillsProvider.notifier).whenReady;
    expect(reloaded.read(skillsProvider).skillById(builtIn.id), isNull);
    expect(
      reloaded.read(skillsProvider).removedBuiltInSkills.single.id,
      builtIn.id,
    );
  });

  test('a restored built-in returns enabled and in shipped order', () async {
    final notifier = container.read(skillsProvider.notifier);
    await notifier.whenReady;
    final skills = BuiltInSkills.all();
    await notifier.removeSkill(skills.first.id);
    await notifier.removeSkill(skills.last.id);

    expect(await notifier.restoreSkill(skills.last.id), isTrue);

    final state = container.read(skillsProvider);
    expect(state.skillById(skills.last.id)?.enabled, isTrue);
    expect(state.removedBuiltInSkills.single.id, skills.first.id);
    // The shipped skills stay in the order the app ships them in, so a
    // restored one sits where it belongs rather than at the end.
    expect(state.builtInSkills.map((skill) => skill.id).toList(), [
      for (final skill in skills)
        if (skill.id != skills.first.id) skill.id,
    ]);
    expect(await notifier.restoreSkill(skills.first.id), isTrue);
    final restored = container.read(skillsProvider);
    expect(restored.removedBuiltInSkills, isEmpty);
    expect(restored.skillById(skills.first.id)?.enabled, isTrue);
    expect(restored.builtInSkills.length, skills.length);
  });

  test('removing an imported skill deletes it for good', () async {
    final skill = Skill.create(name: 'House style', body: 'Write plainly');
    expect(
      SkillStore(registry).save(SkillsSnapshot(customSkills: [skill])),
      isTrue,
    );
    final notifier = container.read(skillsProvider.notifier);
    await notifier.whenReady;
    expect(container.read(skillsProvider).skillById(skill.id), isNotNull);

    expect(await notifier.removeSkill(skill.id), isTrue);

    final state = container.read(skillsProvider);
    expect(state.skillById(skill.id), isNull);
    expect(state.customSkills, isEmpty);
    expect(state.removedBuiltInSkills, isEmpty);
    expect(state.errorMessage, isNull);
    expect(jsonDecode(registry.readAsStringSync())['skills'], isEmpty);
  });

  testWidgets('every skill row offers removal, and removals can be undone', (
    tester,
  ) async {
    // A tall surface so every row and the removed-built-ins section are laid
    // out; the page itself scrolls on a smaller window.
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final skill = Skill.create(name: 'House style', body: 'Write plainly');
    SkillStore(registry).save(SkillsSnapshot(customSkills: [skill]));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SkillsPage()),
      ),
    );
    await tester.pumpAndSettle();

    final builtIn = BuiltInSkills.all().first;
    // One expandable row per active skill: the shipped ones plus the import.
    final rows = BuiltInSkills.all().length + 1;
    expect(find.byType(ExpansionTile), findsNWidgets(rows));
    expect(
      find.byTooltip('Remove built-in'),
      findsNWidgets(BuiltInSkills.all().length),
    );
    expect(find.byTooltip('Delete skill'), findsOneWidget);

    // A built-in leaves the list without a confirmation: it can come back.
    await tester.tap(find.byTooltip('Remove built-in').first);
    await tester.pumpAndSettle();
    expect(find.byType(ExpansionTile), findsNWidgets(rows - 1));
    expect(find.text('Removed built-ins'), findsOneWidget);
    // It is listed below as one that can be put back, not as an active row.
    expect(find.text(builtIn.name), findsOneWidget);
    expect(find.text('Restore'), findsOneWidget);

    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();
    expect(find.byType(ExpansionTile), findsNWidgets(rows));
    expect(find.text('Removed built-ins'), findsNothing);

    // Deleting an imported skill destroys its bundle, so it asks first.
    await tester.tap(find.byTooltip('Delete skill'));
    await tester.pumpAndSettle();
    expect(find.text('Delete ${skill.name}?'), findsOneWidget);
    await tester.tap(find.text('Keep'));
    await tester.pumpAndSettle();
    expect(find.text(skill.name), findsOneWidget);

    await tester.tap(find.byTooltip('Delete skill'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text(skill.name), findsNothing);
    expect(find.byTooltip('Delete skill'), findsNothing);
  });
}
