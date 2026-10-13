import 'package:flutter_test/flutter_test.dart';
import 'package:installm/features/model_selection/domain/model_reasoning.dart';

/// The generation-prompt tail of Qwen 3's own template (`tokenizer_config.json`
/// of Qwen/Qwen3-0.6B), with the message-rendering part left out: what matters
/// here is the branch that decides whether a thought is written. Escapes are
/// spelled the way the template spells them, inside jinja string literals.
const _qwen3 = r'''
{%- for message in messages %}
 {%- if (message.role == "user") %}
 {{- '<|im_start|>' + message.role + '\n' + content + '<|im_end|>' + '\n' }}
 {%- elif message.role == "assistant" %}
 {%- if '</think>' in content %}
 {%- set content = content.split('</think>')[-1].lstrip('\n') %}
 {%- endif %}
 {{- '<|im_start|>' + message.role + '\n' + content + '<|im_end|>\n' }}
 {%- endif %}
{%- endfor %}
{%- if add_generation_prompt %}
 {{- '<|im_start|>assistant\n' }}
 {%- if enable_thinking is defined and enable_thinking is false %}
 {{- '<think>\n\n</think>\n\n' }}
 {%- endif %}
{%- endif %}''';

/// Qwen 3.5's tail (`tokenizer_config.json` of Qwen/Qwen3.5-0.8B): the same
/// variable, and the opposite default — thinking is off unless it is asked for.
const _qwen35 = r'''
{%- if add_generation_prompt %}
 {{- '<|im_start|>assistant\n' }}
 {%- if enable_thinking is defined and enable_thinking is true %}
 {{- '<think>\n' }}
 {%- else %}
 {{- '<think>\n\n</think>\n\n' }}
 {%- endif %}
{%- endif %}''';

/// A chat model with no reasoning control at all, the way most templates are
/// written: the generation prompt is just the assistant prefix.
const _plain = r'''
{%- for message in messages %}
 {{- '<|im_start|>' + message.role + '\n' + message.content + '<|im_end|>\n' }}
{%- endfor %}
{%- if add_generation_prompt %}
 {{- '<|im_start|>assistant\n' }}
{%- endif %}''';

/// Declares the variable but a branch this cannot reproduce: the closing tag is
/// interpolated rather than written out.
const _unrenderable = r'''
{%- if add_generation_prompt %}
 {{- '<|im_start|>assistant\n' }}
 {%- if enable_thinking is defined and enable_thinking is false %}
 {{- close_tag }}
 {%- endif %}
{%- endif %}''';

void main() {
  group('a template the model ships', () {
    test('Qwen 3 answers directly when thinking is switched off', () {
      final reasoning = ModelReasoning.forTemplate(_qwen3);

      expect(reasoning, isNotNull);
      // Two states, no invented scale.
      expect(reasoning!.choices, [
        ReasoningChoice.thinkingOn,
        ReasoningChoice.thinkingOff,
      ]);
      // The model thinks unless it is told otherwise, which is the state the
      // control shows before the user touches it.
      expect(reasoning.defaultChoice, ReasoningChoice.thinkingOn);
      expect(reasoning.prefillFor(ReasoningChoice.thinkingOn), '');
      // The template's own rendering: an empty, already-closed thought block.
      expect(
        reasoning.prefillFor(ReasoningChoice.thinkingOff),
        '<think>\n\n</think>\n\n',
      );
    });

    test('Qwen 3.5 opens a thought block when thinking is switched on', () {
      final reasoning = ModelReasoning.forTemplate(_qwen35)!;

      // Its else branch is the closed block, so that is where an absent
      // variable lands: this model answers directly by default.
      expect(reasoning.defaultChoice, ReasoningChoice.thinkingOff);
      expect(
        reasoning.prefillFor(ReasoningChoice.thinkingOff),
        '<think>\n\n</think>\n\n',
      );
      expect(reasoning.prefillFor(ReasoningChoice.thinkingOn), '<think>\n');
    });

    test('the default needs no prefill at all', () {
      final reasoning = ModelReasoning.forTemplate(_qwen35)!;

      // An unset choice is the model's own behaviour, so it writes exactly what
      // the model would have written anyway.
      expect(
        reasoning.prefillFor(null),
        reasoning.prefillFor(ReasoningChoice.thinkingOff),
      );
    });

    test('a template with no reasoning variable offers no control', () {
      // SmolLM2, Qwen 2.5, Llama, most of the catalog: nothing to show, and
      // nothing to guess at either.
      expect(ModelReasoning.forTemplate(_plain), isNull);
      expect(ModelReasoning.forTemplate(null), isNull);
      expect(ModelReasoning.forTemplate('   '), isNull);
    });

    test('a control it cannot render is no control', () {
      // The variable is there, but the state being chosen is expressed with a
      // variable instead of text: offering it would put the string "close_tag"
      // in the prompt.
      expect(ModelReasoning.forTemplate(_unrenderable), isNull);
    });

    test('an unknown choice falls back to the model default', () {
      final reasoning = ModelReasoning.forTemplate(_qwen3)!;

      expect(
        ReasoningChoice.tryParse('something-else'),
        isNull,
        reason: 'a stored id that is not a state is ignored, not obeyed',
      );
      expect(reasoning.prefillFor(null), '');
    });
  });
}
