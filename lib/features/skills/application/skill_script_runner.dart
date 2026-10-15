import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:crypto/crypto.dart';
import 'package:installm/features/skills/data/skill_bundle_service.dart';
import 'package:installm/features/skills/domain/skill.dart';
import 'package:installm/features/tools/application/tool_registry.dart';
import 'package:installm/features/tools/domain/tool_definition.dart';

/// Per-run process ownership. The small Python supervisor creates a POSIX
/// session, bounds both streams, and kills the group on timeout, cancellation,
/// completion or loss of the app's stdin pipe. This is not an OS sandbox.
class SkillScriptRunner {
  SkillScriptRunner({
    required this.isCurrent,
    this.onResult,
    this.timeout = const Duration(seconds: 15),
    ToolPlatform? platform,
  }) : platform = platform ?? currentToolPlatform();
  final bool Function(Skill) isCurrent;
  final String Function(String)? onResult;
  final Duration timeout;
  final ToolPlatform? platform;
  final Set<Process> _processes = {};
  bool _cancelled = false;
  bool get isRunning => _processes.isNotEmpty;
  void cancel() {
    _cancelled = true;
    for (final process in _processes.toList()) {
      process.kill(ProcessSignal.sigterm);
    }
  }

  static String fingerprint(Skill skill) {
    final names = skill.bundleFiles.keys.toList()..sort();
    return sha256
        .convert(
          utf8.encode(
            jsonEncode({
              for (final name in names) name: skill.bundleFiles[name],
            }),
          ),
        )
        .toString();
  }

  List<ToolEntry> tools(List<Skill> skills) => [
    for (final skill in skills)
      if (skill.requiredCapabilities.contains('shell.execute') &&
          isCurrent(skill))
        for (final script in skill.scriptNames)
          if (SkillBundleService.validPath(script, script: true) &&
              skill.bundleFiles.containsKey(script))
            ToolEntry(
              definition: ToolDefinition(
                name:
                    'skill_run_${sha256.convert(utf8.encode('${skill.id}/$script')).toString().substring(0, 16)}',
                description:
                    'Run ${skill.name}/$script. Working directory: a private temporary copy of this skill bundle. Bundle SHA-256: ${fingerprint(skill)}. Required capabilities: ${skill.requiredCapabilities.join(', ')}. Runs with this app’s host permissions, including possible file/network access; declarations are not a sandbox. Requires Python 3 on macOS/Linux. Approve only scripts you trust.',
                parameters: const [
                  ToolParameter(
                    name: 'arguments',
                    type: ToolParameterType.string,
                    description:
                        'JSON array of literal string arguments; no shell expansion.',
                    required: false,
                    maxLength: 2048,
                  ),
                ],
                risk: ToolRiskLevel.sensitive,
                platforms: const {ToolPlatform.macOS, ToolPlatform.linux},
                timeout: timeout + const Duration(seconds: 5),
              ),
              handler: (args) async {
                final result = await _run(
                  skill,
                  script,
                  args['arguments'] as String? ?? '[]',
                );
                return onResult?.call(result) ?? result;
              },
            ),
  ];

  Future<String> _run(Skill skill, String script, String arguments) async {
    if (platform != ToolPlatform.macOS && platform != ToolPlatform.linux) {
      return 'Skill scripts are supported on macOS/Linux with Python 3. Resources and chat remain available on this device.';
    }
    if (_cancelled ||
        !isCurrent(skill) ||
        !skill.requiredCapabilities.contains('shell.execute')) {
      return 'Script refused: skill assignment, workspace or capabilities changed, or the run was stopped.';
    }
    if (!skill.scriptNames.contains(script) ||
        !SkillBundleService.validPath(script, script: true)) {
      return 'Script refused: choose a declared script.';
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(arguments);
    } catch (_) {
      return 'Script arguments must be a JSON array of strings.';
    }
    if (decoded is! List ||
        decoded.length > 32 ||
        decoded.any(
          (arg) => arg is! String || arg.length > 512 || arg.contains('\u0000'),
        )) {
      return 'Use at most 32 literal string arguments, each at most 512 characters.';
    }
    Directory? directory;
    Process? process;
    Timer? eligibilityWatch;
    try {
      if (skill.bundleFiles.length > SkillBundleService.maxFiles) {
        return 'Script refused: bundle has too many files. Re-import it.';
      }
      directory = await Directory.systemTemp.createTemp('installm-skill-');
      var bytes = 0;
      for (final entry in skill.bundleFiles.entries) {
        final data = utf8.encode(entry.value);
        bytes += data.length;
        if (!SkillBundleService.validPath(
              entry.key,
              script: skill.scriptNames.contains(entry.key),
            ) ||
            data.length > SkillBundleService.maxFileBytes ||
            bytes > SkillBundleService.maxBundleBytes) {
          return 'Script refused: invalid or oversized bundle. Re-import it.';
        }
        final file = File(p.join(directory.path, entry.key));
        await file.parent.create(recursive: true);
        await file.writeAsBytes(data, flush: true);
      }
      if (!await File(p.join(directory.path, script)).exists()) {
        return 'Script file is missing. Re-import the bundle.';
      }
      String? python;
      for (final path in [
        '/opt/homebrew/bin/python3',
        '/usr/local/bin/python3',
        '/usr/bin/python3',
      ]) {
        if (await File(path).exists()) {
          python = path;
          break;
        }
      }
      if (python == null) {
        return 'Install Python 3 to run skill scripts on this desktop.';
      }
      if (_cancelled || !isCurrent(skill)) {
        return 'Script refused: eligibility changed before launch.';
      }
      process = await Process.start(
        python,
        ['-I', '-u', '-c', _supervisor],
        workingDirectory: directory.path,
        includeParentEnvironment: false,
        environment: const {
          'PATH': '/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin',
          'LANG': 'C.UTF-8',
        },
      );
      _processes.add(process);
      eligibilityWatch = Timer.periodic(const Duration(milliseconds: 50), (_) {
        try {
          if (_cancelled || !isCurrent(skill)) {
            process?.kill(ProcessSignal.sigterm);
          }
        } catch (_) {
          process?.kill(ProcessSignal.sigterm);
        }
      });
      if (_cancelled || !isCurrent(skill)) {
        process.kill(ProcessSignal.sigterm);
        return 'Script cancelled before launch.';
      }
      final output = <int>[];
      final errors = <int>[];
      final out = process.stdout.listen((chunk) {
        if (output.length < 65536) {
          output.addAll(chunk.take(65536 - output.length));
        }
      });
      final err = process.stderr.listen((chunk) {
        if (errors.length < 1024) {
          errors.addAll(chunk.take(1024 - errors.length));
        }
      });
      final outDone = out.asFuture<void>();
      final errDone = err.asFuture<void>();
      process.stdin.writeln(
        jsonEncode({
          'command': [
            script.endsWith('.py') ? python : '/bin/sh',
            if (script.endsWith('.py')) '-I',
            script,
            ...decoded,
          ],
          'timeout': timeout.inMilliseconds / 1000,
        }),
      );
      await process.stdin.flush();
      await process.exitCode.timeout(
        timeout + const Duration(seconds: 3),
        onTimeout: () {
          process!.kill(ProcessSignal.sigterm);
          return -1;
        },
      );
      await outDone.timeout(const Duration(seconds: 1), onTimeout: () {});
      await errDone.timeout(const Duration(seconds: 1), onTimeout: () {});
      await out.cancel();
      await err.cancel();
      if (_cancelled) return 'Script stopped by the user.';
      if (!isCurrent(skill)) {
        return 'Script result discarded: eligibility changed.';
      }
      if (output.isEmpty) {
        return 'Script runner could not start. Check that Python 3 is available and allowed on this desktop.';
      }
      final result = jsonDecode(utf8.decode(output)) as Map;
      return 'Script ${result['reason']}; exit ${result['exitCode']}.\nstdout:\n${result['stdout']}\nstderr:\n${result['stderr']}${result['truncated'] == true ? '\n[Output truncated]' : ''}';
    } catch (_) {
      return 'Could not run this script. Check the declared files and Python 3 installation.';
    } finally {
      eligibilityWatch?.cancel();
      if (process != null) {
        process.kill(ProcessSignal.sigterm);
        _processes.remove(process);
        await process.stdin.close().catchError((_) {});
      }
      if (directory != null && await directory.exists()) {
        try {
          await directory.delete(recursive: true);
        } catch (_) {}
      }
    }
  }
}

// Trusted supervisor source, never assembled from a model-provided command.
const _supervisor = r'''
import json, os, selectors, signal, subprocess, sys, time
stopping = False
def stop(signum, frame):
    global stopping
    stopping = True
signal.signal(signal.SIGTERM, stop)
signal.signal(signal.SIGINT, stop)
proc = None
try:
    config = json.loads(sys.stdin.buffer.readline())
    proc = subprocess.Popen(config['command'], stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
    def kill_group():
        try: os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError: pass
    sel = selectors.DefaultSelector()
    sel.register(proc.stdout, selectors.EVENT_READ, 'stdout')
    sel.register(proc.stderr, selectors.EVENT_READ, 'stderr')
    sel.register(sys.stdin.buffer, selectors.EVENT_READ, 'parent')
    buffers = {'stdout': bytearray(), 'stderr': bytearray()}
    remaining = 8192
    truncated = False
    deadline = time.monotonic() + min(max(config['timeout'], 0.05), 60)
    reason = 'completed'
    ended = None
    while True:
        now = time.monotonic()
        if stopping or now >= deadline:
            reason = 'cancelled' if stopping else 'timed out'
            kill_group()
            ended = ended or now
        if proc.poll() is not None:
            kill_group() # also retire background descendants after normal exit
            ended = ended or now
        for key, _ in sel.select(0.02):
            data = os.read(key.fd, 4096)
            if key.data == 'parent':
                if not data: stopping = True
                continue
            if not data:
                sel.unregister(key.fileobj)
                continue
            take = min(len(data), remaining)
            buffers[key.data].extend(data[:take])
            remaining -= take
            if take < len(data): truncated = True
        if ended is not None and (len(sel.get_map()) <= 1 or now - ended > 0.2): break
    kill_group()
    code = proc.wait(timeout=1)
    print(json.dumps({'reason': reason, 'exitCode': code,
        'stdout': buffers['stdout'].decode('utf-8', 'replace'),
        'stderr': buffers['stderr'].decode('utf-8', 'replace'), 'truncated': truncated}))
finally:
    if proc is not None:
        try: os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError: pass
''';
