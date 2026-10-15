import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:installm/features/skills/application/skill_script_runner.dart';
import 'package:installm/features/skills/domain/skill.dart';
import 'package:installm/features/tools/application/tool_registry.dart';
import 'package:installm/features/tools/domain/tool_call.dart';
import 'package:installm/features/tools/domain/tool_definition.dart';
import 'package:installm/features/tools/domain/tool_execution_result.dart';

class Gate implements ToolPermissionGate {
  bool allow = false;
  int requests = 0;
  void Function()? onAsk;
  @override
  Future<bool> requestApproval(ToolApprovalRequest request) async {
    requests++;
    expect(request.tool.description, contains('not a sandbox'));
    expect(request.tool.description, contains('SHA-256'));
    onAsk?.call();
    return allow;
  }
}

void main() {
  Skill skill(
    String code, {
    Set<String> capabilities = const {'shell.execute'},
  }) => Skill.create(
    id: 'script',
    name: 'check',
    requiredCapabilities: capabilities,
    scriptNames: ['scripts/check.sh'],
    bundleFiles: {'scripts/check.sh': code},
  );
  Future<String> execute(
    SkillScriptRunner runner,
    Skill skill, {
    Gate? gate,
    String args = '[]',
  }) async {
    final tools = runner.tools([skill]);
    expect(tools, hasLength(1));
    final registry = ToolRegistry(
      tools: tools,
      platform: ToolPlatform.linux,
      permissionGate: gate ?? (Gate()..allow = true),
    );
    final result = await registry.execute(
      ToolCall(
        toolName: tools.single.definition.name,
        arguments: {'arguments': args},
      ),
    );
    return result.output;
  }

  test('unassigned/capability-missing skills expose no executable tools', () {
    expect(
      SkillScriptRunner(isCurrent: (_) => false).tools([skill('echo no')]),
      isEmpty,
    );
    expect(
      SkillScriptRunner(
        isCurrent: (_) => true,
      ).tools([skill('echo no', capabilities: {})]),
      isEmpty,
    );
  });
  test('refusal and revocation during approval launch nothing', () async {
    final root = Directory.systemTemp.createTempSync('script-gate-');
    addTearDown(() => root.deleteSync(recursive: true));
    final marker = File('${root.path}/launched');
    final s = skill('touch "\$1"');
    var current = true;
    final runner = SkillScriptRunner(isCurrent: (_) => current);
    final gate = Gate();
    expect(
      await execute(runner, s, gate: gate, args: jsonEncode([marker.path])),
      contains('did not allow'),
    );
    expect(marker.existsSync(), isFalse);
    gate.allow = true;
    gate.onAsk = () => current = false;
    expect(
      await execute(runner, s, gate: gate, args: jsonEncode([marker.path])),
      contains('refused'),
    );
    expect(marker.existsSync(), isFalse);
    expect(gate.requests, 2);
    expect(runner.isRunning, isFalse);
  });
  test('mobile registry refuses script execution', () async {
    final runner = SkillScriptRunner(
      isCurrent: (_) => true,
      platform: ToolPlatform.android,
    );
    final tools = runner.tools([skill('echo unavailable')]);
    final result =
        await ToolRegistry(
          tools: tools,
          platform: ToolPlatform.android,
        ).execute(
          ToolCall(toolName: tools.single.definition.name, arguments: const {}),
        );
    expect(result.status, ToolExecutionStatus.unsupported);
    expect(runner.isRunning, isFalse);
  });
  test(
    'real script receives literal arguments, no app environment, and bounded output',
    () async {
      final runner = SkillScriptRunner(isCurrent: (_) => true);
      final output = await execute(
        runner,
        skill(
          'printf "%s\\n" "\$1"; printf "err\\n" >&2; env; i=0; while [ \$i -lt 4000 ]; do printf xxxxx; i=\$((i+1)); done; exit 7',
        ),
        args: jsonEncode(['\$(touch should-not-exist)']),
      );
      expect(output, contains('exit 7'));
      expect(output, contains('\$(touch should-not-exist)'));
      expect(output, contains('err'));
      expect(output, contains('Output truncated'));
      expect(output.length, lessThan(9000));
      expect(output, isNot(contains('CODEX_HOME=')));
      expect(runner.isRunning, isFalse);
    },
    skip: !Platform.isLinux,
  );
  test(
    'timeout kills the script and its child before delayed side effects',
    () async {
      final root = Directory.systemTemp.createTempSync('script-timeout-');
      addTearDown(() => root.deleteSync(recursive: true));
      final marker = File('${root.path}/late');
      final runner = SkillScriptRunner(
        isCurrent: (_) => true,
        timeout: const Duration(milliseconds: 100),
      );
      final output = await execute(
        runner,
        skill('(sleep 0.5; touch "\$1") & wait'),
        args: jsonEncode([marker.path]),
      );
      expect(output, contains('timed out'));
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(marker.existsSync(), isFalse);
      expect(runner.isRunning, isFalse);
    },
    skip: !Platform.isLinux,
  );
  test('user stop kills running work and retires its children', () async {
    final root = Directory.systemTemp.createTempSync('script-stop-');
    addTearDown(() => root.deleteSync(recursive: true));
    final ready = File('${root.path}/ready');
    final late = File('${root.path}/late');
    final runner = SkillScriptRunner(isCurrent: (_) => true);
    final future = execute(
      runner,
      skill('touch "\$1"; (sleep 0.5; touch "\$2") & wait'),
      args: jsonEncode([ready.path, late.path]),
    );
    for (var i = 0; i < 200 && !ready.existsSync(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(ready.existsSync(), isTrue);
    runner.cancel();
    expect(await future, contains('stopped'));
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(late.existsSync(), isFalse);
  }, skip: !Platform.isLinux);
}
