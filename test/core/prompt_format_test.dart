import 'package:flutter_test/flutter_test.dart';
import 'package:installm/core/services/hugging_face_repository_service.dart';
import 'package:installm/core/utils/llm_prompt_utils.dart';
import 'package:installm/features/model_selection/data/model_prompt_format_service.dart';
import 'package:installm/features/model_selection/domain/gguf_metadata.dart';
import 'package:installm/features/model_selection/domain/llm_model.dart';

/// A prompt format is a property of the file: a repository import can be
/// ChatML, Llama 2, Llama 3, Alpaca, Gemma or Phi-3 shaped, and a base
/// completion model declares no template at all. These pin the detection, the
/// prompt each format builds, and the base-model decision.
void main() {
  const chatmlTemplate =
      "{% for message in messages %}<|im_start|>{{ message['role'] }}\n"
      "{{ message['content'] }}<|im_end|>{% endfor %}";
  const llama2Template =
      "{% for message in messages %}{{ '<s>[INST] ' + message['content'] + "
      "' [/INST]' }}{% endfor %}";
  const alpacaTemplate =
      '{% if messages %}{{ "### Instruction:\n" + messages[0]["content"] }}'
      '{% endif %}';
  const gemmaTemplate =
      "{{ '<start_of_turn>user\n' + messages[0]['content'] + '<end_of_turn>' }}";
  const phi3Template =
      "{{ '<|user|>\n' + messages[0]['content'] + '<|end|>' }}";
  // TinyLlama Chat and the Zephyr family: `<|role|>` markers, `</s>` closing
  // every turn, no `<|end|>`.
  const zephyrTemplate =
      "{% for message in messages %}{{ '<|user|>\\n' + message['content'] + "
      'eos_token }}{% endfor %}';
  const llama3Template =
      "{{ '<|start_header_id|>user<|end_header_id|>\n\n' + "
      "messages[0]['content'] }}";

  group('promptFormatFromTemplate', () {
    test('reads the family the template declares', () {
      expect(promptFormatFromTemplate(chatmlTemplate), 'chatml');
      expect(promptFormatFromTemplate(llama2Template), 'llama2');
      expect(promptFormatFromTemplate(alpacaTemplate), 'alpaca');
      expect(promptFormatFromTemplate(gemmaTemplate), 'gemma');
      expect(promptFormatFromTemplate(phi3Template), 'phi3');
      expect(promptFormatFromTemplate(zephyrTemplate), 'zephyr');
      expect(promptFormatFromTemplate(llama3Template), 'llama3');
    });

    test('a missing or blank template is not a chat format', () {
      expect(promptFormatFromTemplate(null), isNull);
      expect(promptFormatFromTemplate(''), isNull);
      expect(promptFormatFromTemplate('   '), isNull);
    });

    test('an unrecognised template still gets a usable format', () {
      expect(promptFormatFromTemplate('{{ custom }}'), 'chatml');
    });
  });

  group('buildModelChatPrompt', () {
    final messages = [
      const LlmPromptMessage.user('Say hello'),
      const LlmPromptMessage.assistant('Hello!'),
      const LlmPromptMessage.user('And again'),
    ];

    test(
      'llama2 wraps every turn in [INST] and keeps the system prompt once',
      () {
        final prompt = buildModelChatPrompt(
          messages,
          systemPrompt: 'Be brief',
          promptFormatId: 'llama2',
        ).prompt;

        expect(
          prompt,
          startsWith('[INST] <<SYS>>\nBe brief\n<</SYS>>\n\nSay hello [/INST]'),
        );
        expect(prompt, contains(' Hello! </s>'));
        expect(prompt, endsWith('[INST] And again [/INST]'));
        expect('[INST]'.allMatches(prompt).length, 2);
      },
    );

    test('alpaca writes Instruction and Response sections', () {
      final prompt = buildModelChatPrompt(
        messages,
        systemPrompt: 'Be brief',
        promptFormatId: 'alpaca',
      ).prompt;

      expect(prompt, contains('### Instruction:'));
      expect(prompt, contains('### Response:'));
      expect(prompt, endsWith('### Response:\n'));
    });

    test('llama3 writes header-tagged turns and opens the assistant', () {
      final prompt = buildModelChatPrompt(
        messages,
        systemPrompt: 'Be brief',
        promptFormatId: 'llama3',
      ).prompt;

      expect(prompt, contains('<|start_header_id|>user<|end_header_id|>'));
      expect(prompt, contains('<|eot_id|>'));
      expect(
        prompt,
        endsWith('<|start_header_id|>assistant<|end_header_id|>\n\n'),
      );
    });

    test('zephyr closes every turn with the end-of-sequence token', () {
      final prompt = buildModelChatPrompt(
        messages,
        systemPrompt: 'Be brief',
        promptFormatId: 'zephyr',
      ).prompt;

      expect(prompt, startsWith('<|system|>\nBe brief</s>\n'));
      expect(prompt, contains('<|user|>\nSay hello</s>\n'));
      expect(prompt, endsWith('<|assistant|>\n'));
    });

    test('phi3 and gemma use their own turn markers', () {
      expect(
        buildModelChatPrompt(messages, promptFormatId: 'phi3').prompt,
        contains('<|user|>\nSay hello<|end|>'),
      );
      expect(
        buildModelChatPrompt(messages, promptFormatId: 'gemma').prompt,
        endsWith('<start_of_turn>model\n'),
      );
    });

    test('chatml is unchanged', () {
      expect(
        buildModelChatPrompt(messages, promptFormatId: 'chatml').prompt,
        contains('<|im_start|>user\nSay hello<|im_end|>'),
      );
    });
  });

  test('each format stops on its own end-of-turn marker', () {
    expect(modelStopToken('chatml'), '<|im_end|>');
    expect(modelStopToken('llama2'), '</s>');
    expect(modelStopToken('llama3'), '<|eot_id|>');
    expect(modelStopToken('phi3'), '<|end|>');
    expect(modelStopToken('zephyr'), '</s>');
    expect(modelStopToken('gemma'), '<end_of_turn>');
    expect(modelStopToken('alpaca'), '</s>');
  });

  group('ModelPromptFormatService', () {
    LlmModel modelWithTemplate(String? template, {String recorded = 'chatml'}) {
      return LlmModel(
        id: 'test-model',
        name: 'Test',
        parameterSize: '1B',
        description: '',
        promptFormatId: recorded,
        ggufMetadata: GgufMetadata(
          architecture: 'llama',
          name: 'test',
          version: 3,
          kvCount: 10,
          tensorCount: 10,
          fileSizeBytes: 1,
          parameterCount: 1,
          quantization: 'Q4_K_M',
          chatTemplate: template,
        ),
      );
    }

    test('the file template wins over the recorded format', () async {
      final service = ModelPromptFormatService();
      final resolved = await service.resolve(
        modelWithTemplate(llama2Template, recorded: 'chatml'),
      );

      expect(resolved.promptFormatId, 'llama2');
      expect(resolved.isInstruct, isTrue);
    });

    test('a file without a template is a base model, not a chat model', () {
      final base = ModelPromptFormat.fromTemplate(null);
      expect(base.isInstruct, isFalse);
      expect(ModelPromptFormat.fromTemplate('').isInstruct, isFalse);
      expect(ModelPromptFormat.fromTemplate(chatmlTemplate).isInstruct, isTrue);
    });

    test(
      'an unreadable file keeps the recorded format instead of guessing',
      () async {
        // Nothing on disk to read and no template in the record: the service must
        // not declare the model a base one on the strength of a read failure.
        final service = ModelPromptFormatService();
        final resolved = await service.resolve(
          modelWithTemplate(null, recorded: 'llama2'),
        );

        expect(resolved.isInstruct, isTrue);
        expect(resolved.promptFormatId, 'llama2');
      },
    );

    test('the resolved format is remembered per model', () async {
      final service = ModelPromptFormatService();
      final model = modelWithTemplate(alpacaTemplate);

      expect((await service.resolve(model)).promptFormatId, 'alpaca');
      expect((await service.resolve(model)).promptFormatId, 'alpaca');
    });
  });

  group('chatTemplateFromTokenizerConfig', () {
    test('accepts a plain template string', () {
      expect(
        HuggingFaceRepositoryService.chatTemplateFromTokenizerConfig(
          llama2Template,
        ),
        llama2Template,
      );
    });

    test('picks the default entry from a named template list', () {
      final raw = [
        {'name': 'tool_use', 'template': chatmlTemplate},
        {'name': 'default', 'template': llama2Template},
      ];

      expect(
        HuggingFaceRepositoryService.chatTemplateFromTokenizerConfig(raw),
        llama2Template,
      );
    });

    test('a missing or blank template reads as none', () {
      expect(
        HuggingFaceRepositoryService.chatTemplateFromTokenizerConfig(null),
        isNull,
      );
      expect(
        HuggingFaceRepositoryService.chatTemplateFromTokenizerConfig('  '),
        isNull,
      );
      expect(
        HuggingFaceRepositoryService.chatTemplateFromTokenizerConfig(
          <Object>[],
        ),
        isNull,
      );
    });
  });

  test('the formats the app builds are the ones it claims to support', () {
    for (final id in [
      'chatml',
      'gemma3',
      'gemma',
      'llama2',
      'llama3',
      'alpaca',
      'phi3',
      'zephyr',
    ]) {
      expect(isKnownPromptFormat(id), isTrue, reason: id);
    }
    expect(isKnownPromptFormat('nonsense'), isFalse);
  });
}
