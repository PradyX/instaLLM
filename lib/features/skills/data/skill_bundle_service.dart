import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:installm/features/skills/domain/skill.dart';
import 'package:installm/features/skills/domain/skill_parser.dart';

/// Explicit, bounded snapshots of user-selected bundles. Nothing executes here.
class SkillBundleService {
  const SkillBundleService();
  static const maxFileBytes = 64 * 1024;
  static const maxBundleBytes = 256 * 1024;
  static const maxFiles = 32;

  static bool validPath(String path, {bool script = false}) {
    if (path.length > 200 || path.contains('\\') || path.contains('\u0000')) {
      return false;
    }
    final parts = path.split('/');
    if (parts.length < 2 ||
        parts.any(
          (v) => v.isEmpty || v == '.' || v == '..' || v.startsWith('.'),
        )) {
      return false;
    }
    if (script) {
      return parts.first == 'scripts' &&
          (path.endsWith('.sh') || path.endsWith('.py'));
    }
    return const {
          'resources',
          'references',
          'templates',
          'examples',
        }.contains(parts.first) &&
        const {
          '.md',
          '.txt',
          '.json',
          '.csv',
          '.yaml',
          '.yml',
        }.contains(p.posix.extension(path).toLowerCase());
  }

  static Future<String> readText(File file) async {
    final input = await file.open();
    try {
      final bytes = await input.read(maxFileBytes + 1);
      if (bytes.length > maxFileBytes) {
        throw const FormatException('Skill files must be at most 64 KiB.');
      }
      final text = utf8.decode(bytes);
      if (text.contains('\u0000')) {
        throw const FormatException('Choose UTF-8 text skill files.');
      }
      return text;
    } finally {
      await input.close();
    }
  }

  Future<Skill> importFile(File manifest) async {
    if (await FileSystemEntity.type(manifest.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw const FormatException(
        'Choose a regular SKILL.md file, not a link.',
      );
    }
    final root = await manifest.parent.resolveSymbolicLinks();
    final text = await readText(manifest);
    final parsed = SkillParser.parse(
      text,
      fallbackName: p.basenameWithoutExtension(manifest.path),
    );
    final resources = parsed.resources.toSet().toList();
    final scripts = parsed.scripts.toSet().toList();
    if (resources.length + scripts.length > maxFiles) {
      throw const FormatException(
        'A skill may declare at most 32 supporting files.',
      );
    }
    final contents = <String, String>{};
    var bytes = utf8.encode(text).length;
    for (final name in [...resources, ...scripts]) {
      if (!validPath(name, script: scripts.contains(name))) {
        throw FormatException('Invalid skill file path: $name');
      }
      var current = root;
      final parts = name.split('/');
      for (var i = 0; i < parts.length; i++) {
        current = p.join(current, parts[i]);
        final type = await FileSystemEntity.type(current, followLinks: false);
        if (type !=
            (i == parts.length - 1
                ? FileSystemEntityType.file
                : FileSystemEntityType.directory)) {
          throw FormatException(
            'Skill file is missing or contains a link: $name',
          );
        }
      }
      final file = File(current);
      if (!p.isWithin(root, await file.resolveSymbolicLinks())) {
        throw const FormatException('Skill file leaves its bundle.');
      }
      final content = await readText(file);
      bytes += utf8.encode(content).length;
      if (bytes > maxBundleBytes) {
        throw const FormatException('A skill bundle must be at most 256 KiB.');
      }
      contents[name] = content;
    }
    return Skill.create(
      name: parsed.name,
      description: parsed.description,
      version: parsed.version,
      requiredCapabilities: parsed.permissions.toSet(),
      body: parsed.body,
      resourceNames: resources,
      scriptNames: scripts,
      bundleFiles: contents,
    );
  }
}
