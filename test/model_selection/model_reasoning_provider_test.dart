import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pocket_llm/features/model_selection/domain/model_reasoning.dart';
import 'package:pocket_llm/features/model_selection/presentation/model_reasoning_provider.dart';
import 'package:pocket_llm/features/model_selection/presentation/model_selection_controller.dart';

import 'support/gguf_test_builder.dart';

/// Qwen 3's own template, trimmed to what decides the reasoning control: the
/// assistant branch that parses past thoughts — where the same variable name
/// shows up in a `split` and must not be mistaken for the setting — and the
/// generation prompt that appends a closed thought block when thinking is off.
const _qwen3Template = r'''
{%- for message in messages %}
 {%- elif message.role == "assistant" %}
 {%- if ' response' in content %}
 {%- set content = content.split('</think>')[-1].lstrip('\n') %}
 {%- endif %}
 {{- '<|im_start|>' + message.role + '\n' + content + '<|im_end|>\n' }}
{%- endfor %}
{%- if add_generation_prompt %}
 {{- '<|im_start|>assistant\n' }}
 {%- if enable_thinking is defined and enable_thinking is false %}
 {{- '<think>\n\n</think>\n\n' }}
 {%- endif %}
{%- endif %}''';

/// A chat model with no reasoning control: the generation prompt is the
/// assistant prefix and nothing else.
const _plainTemplate = r'''
{%- if add_generation_prompt %}
 {{- '<|im_start|>assistant\n' }}
{%- endif %}''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Waits for the provider to answer, reading it the way a surface does.
  ///
  /// Awaiting `.future` directly would be wrong here: the provider re-runs
  /// whenever the catalog reports something new (a capability refresh, a
  /// finished download), and awaiting one of those runs leaves the test holding
  /// a future the next rebuild replaces.
  Future<ModelReasoning?> reasoningFor(
    ProviderContainer container,
    String modelId,
  ) async {
    for (var attempt = 0; attempt < 300; attempt++) {
      final value = container.read(modelReasoningProvider(modelId));
      if (!value.isLoading) return value.valueOrNull;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    return container.read(modelReasoningProvider(modelId)).valueOrNull;
  }

  late Directory tempDir;

  /// Writes a model the app will treat as installed: a real GGUF with the
  /// template a thinking model ships, in the folder the app looks in.
  Future<void> installModel({
    required String fileName,
    required String template,
  }) async {
    final bytes = GgufTestBuilder(version: 3)
        .string('general.architecture', 'qwen3')
        .string('general.name', 'Test Model')
        .string('tokenizer.chat_template', template)
        .build();
    final file = File(p.join(tempDir.path, 'models', fileName));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('pocketllm_reasoning');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async => null,
        );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          null,
        );
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  /// A launch with the controller loaded, the way a surface sees it.
  Future<ProviderContainer> launched() async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.listen(modelSelectionControllerProvider, (previous, next) {});
    for (var attempt = 0; attempt < 300; attempt++) {
      final models = container.read(modelSelectionControllerProvider).models;
      if (models.any((model) => model.isDownloaded)) break;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    return container;
  }

  test(
    'an installed thinking model offers the states its file declares',
    () async {
      await installModel(
        fileName: 'qwen3-0.6b-q4_k_m.gguf',
        template: _qwen3Template,
      );
      final container = await launched();

      final reasoning = await reasoningFor(container, 'qwen-3-0.6b');

      expect(reasoning, isNotNull);
      expect(reasoning!.defaultChoice, ReasoningChoice.thinkingOn);
      expect(reasoning.prefillFor(ReasoningChoice.thinkingOn), '');
      // The file's own text, escapes resolved: what the prompt will carry when
      // the user asks this model to answer instead of to think.
      expect(
        reasoning.prefillFor(ReasoningChoice.thinkingOff),
        '<think>\n\n</think>\n\n',
      );
    },
  );

  test('an installed model that declares none offers no control', () async {
    await installModel(
      fileName: 'qwen2.5-0.5b-instruct-q4_k_m.gguf',
      template: _plainTemplate,
    );
    final container = await launched();

    expect(await reasoningFor(container, 'qwen-2.5-0.5b'), isNull);
    // And a model the app does not know at all is nothing to show either.
    expect(await reasoningFor(container, 'not-a-model'), isNull);
  });
}
