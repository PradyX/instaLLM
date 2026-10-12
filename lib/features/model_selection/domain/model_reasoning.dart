/// What a model's own chat template says about reasoning.
///
/// Read from `tokenizer.chat_template` in the installed GGUF, the same way
/// `GgufMetadata.supportsToolCalling` is read: a capability belongs to the file,
/// not to its name. The templates that carry a reasoning control test one
/// variable — `enable_thinking` — where the assistant reply begins, and each
/// branch says what that state looks like on the wire: Qwen 3 appends a closed,
/// empty thought block when thinking is off, Qwen 3.5 opens one when it is on
/// and appends that same closed block otherwise. This type keeps those two
/// renderings and which one the model does on its own, so the composer can
/// offer exactly what the model declares and the prompt can be built the way
/// the template would have built it.
///
/// Nothing here invents a scale. A model that names no such variable — or names
/// it without saying what it renders — reports null and gets no control, rather
/// than a level picker that would be a decoration.
library;

/// The states a reasoning control can be in.
///
/// Two states, because that is what the templates declare: a model either
/// writes a thought before answering or answers directly. Effort scales
/// (`reasoning_effort`, as gpt-oss uses) live in templates that render them
/// into the system message through chat-template kwargs, which this app's
/// runtime does not expose yet; they are left alone rather than half-implemented.
enum ReasoningChoice {
  thinkingOn('on', 'Thinking'),
  thinkingOff('off', 'No thinking');

  const ReasoningChoice(this.id, this.label);

  /// Stored form; stable, because a choice is persisted per model.
  final String id;

  /// What the composer shows for this state.
  final String label;

  static ReasoningChoice? tryParse(String? value) {
    for (final choice in values) {
      if (choice.id == value) return choice;
    }
    return null;
  }
}

class ModelReasoning {
  const ModelReasoning({required this.defaultChoice, required this.prefills});

  /// The state the model is in when the prompt says nothing about it.
  ///
  /// Derived, not assumed: the branch a template takes when the variable is
  /// absent is the model's own default, which is thinking off for Qwen 3.5 and
  /// thinking on for Qwen 3.
  final ReasoningChoice defaultChoice;

  /// What the template appends after the assistant prefix for each state.
  final Map<ReasoningChoice, String> prefills;

  List<ReasoningChoice> get choices => ReasoningChoice.values;

  /// The text to write after `<|im_start|>assistant\n` for [choice]; empty when
  /// the template appends nothing in that state.
  String prefillFor(ReasoningChoice? choice) =>
      prefills[choice ?? defaultChoice] ?? '';

  static const String _addGenerationPrompt = 'add_generation_prompt';
  static const String _thinkingVariable = 'enable_thinking';

  /// The reasoning a template declares, or null when it declares none.
  ///
  /// The variable is looked for in the generation-prompt section — the part
  /// that renders the beginning of the reply — because earlier in a template
  /// the same name can appear while rendering past messages, where appending it
  /// would mean nothing. Both branches of the block must render as plain text;
  /// a branch that interpolates message content is not something this can
  /// reproduce, so the model reports no control instead of a wrong one.
  static ModelReasoning? forTemplate(String? template) {
    final raw = template;
    if (raw == null || raw.trim().isEmpty) return null;

    final start = raw.lastIndexOf(_addGenerationPrompt);
    if (start < 0) return null;

    final region = raw.substring(start);
    final variableAt = region.indexOf(_thinkingVariable);
    if (variableAt < 0) return null;

    final block = _thinkingBlock(region, variableAt);
    if (block == null) return null;

    // `enable_thinking is false` turns thinking off, `is true` turns it on; a
    // bare test is truthy, which is the same direction as true.
    final ifChoice = block.condition.contains('false')
        ? ReasoningChoice.thinkingOff
        : ReasoningChoice.thinkingOn;
    final elseChoice = ifChoice == ReasoningChoice.thinkingOff
        ? ReasoningChoice.thinkingOn
        : ReasoningChoice.thinkingOff;

    final prefills = <ReasoningChoice, String>{
      ifChoice: block.ifPrefill,
      elseChoice: block.elsePrefill,
    };
    if (prefills[ifChoice] == prefills[elseChoice]) return null;

    // The variable is absent unless something supplies it, so the model starts
    // in the branch the condition sends it to when the value is undefined.
    return ModelReasoning(defaultChoice: elseChoice, prefills: prefills);
  }

  /// The `if enable_thinking …` block that contains [variableAt], with each
  /// branch's text output resolved.
  static _ThinkingBlock? _thinkingBlock(String region, int variableAt) {
    final tagStart = region.lastIndexOf('{%', variableAt);
    if (tagStart < 0) return null;

    final tagEnd = region.indexOf('%}', tagStart);
    if (tagEnd < 0) return null;
    final condition = region.substring(tagStart, tagEnd);
    if (!condition.contains('if')) return null;

    // Walk the block to its `endif`, so the branches are known before they are
    // read; an `elif` adds a third state this type has no name for.
    var depth = 0;
    var elseAt = -1;
    var index = tagStart;
    var end = -1;
    while (index < region.length) {
      final next = region.indexOf('{%', index);
      if (next < 0) break;
      final close = region.indexOf('%}', next);
      if (close < 0) break;
      final tag = region.substring(next + 2, close).replaceAll('-', '').trim();

      if (tag.startsWith('if')) {
        depth++;
      } else if (tag.startsWith('endif')) {
        depth--;
        if (depth == 0) {
          end = next;
          break;
        }
      } else if (tag.startsWith('elif')) {
        return null;
      } else if (tag.startsWith('else') && depth == 1) {
        elseAt = next;
      }

      index = close;
    }
    if (end < 0) return null;

    final ifBody = region.substring(tagEnd + 2, elseAt < 0 ? end : elseAt);
    final elseTagEnd = elseAt < 0 ? -1 : region.indexOf('%}', elseAt);
    if (elseAt >= 0 && elseTagEnd < 0) return null;
    final elseBody = elseAt < 0 ? '' : region.substring(elseTagEnd + 2, end);

    final ifPrefill = _textOutput(ifBody);
    final elsePrefill = _textOutput(elseBody);
    if (ifPrefill == null || elsePrefill == null) return null;

    return _ThinkingBlock(
      condition: condition,
      ifPrefill: ifPrefill,
      elsePrefill: elsePrefill,
    );
  }

  /// The text [body] renders, or null when it cannot be reduced to text.
  ///
  /// Whitespace between tags is trimmed away by Jinja's `{%-` and `-}}`, so only
  /// text with content counts; `{{ … }}` must be string literals, possibly
  /// added together, and anything else means this branch is not reproducible.
  static String? _textOutput(String body) {
    final buffer = StringBuffer();
    var index = 0;

    while (index < body.length) {
      final open = body.indexOf('{{', index);
      final text = open < 0
          ? body.substring(index)
          : body.substring(index, open);
      if (text.trim().isNotEmpty) return null;

      if (open < 0) break;
      final close = body.indexOf('}}', open);
      if (close < 0) return null;

      final expression = body
          .substring(open + 2, close)
          .replaceAll(RegExp(r'^\s*-'), '')
          .replaceAll(RegExp(r'-\s*$'), '')
          .trim();
      final literal = _concatenatedLiterals(expression);
      if (literal == null) return null;
      buffer.write(literal);

      index = close + 2;
    }

    return buffer.toString();
  }

  /// The value of a `'…'` expression, or of literals added together, or null
  /// when the expression is anything more than text.
  static String? _concatenatedLiterals(String expression) {
    final buffer = StringBuffer();
    final parts = expression.split('+');

    for (final rawPart in parts) {
      final part = rawPart.trim();
      if (part.length < 2) return null;

      final quote = part[0];
      if (quote != "'" && quote != '"') return null;
      if (!part.endsWith(quote)) return null;

      buffer.write(_unescape(part.substring(1, part.length - 1), quote));
    }

    return buffer.toString();
  }

  /// Turns the template's own escapes into the characters they stand for.
  static String _unescape(String value, String quote) {
    final buffer = StringBuffer();
    var index = 0;

    while (index < value.length) {
      final character = value[index];
      if (character != r'\' || index + 1 >= value.length) {
        buffer.write(character);
        index++;
        continue;
      }

      final next = value[index + 1];
      switch (next) {
        case 'n':
          buffer.write('\n');
        case 't':
          buffer.write('\t');
        case 'r':
          buffer.write('\r');
        case r'\':
          buffer.write(r'\');
        case "'":
          buffer.write("'");
        case '"':
          buffer.write('"');
        default:
          buffer.write(next);
      }
      index += 2;
    }

    return buffer.toString();
  }
}

class _ThinkingBlock {
  const _ThinkingBlock({
    required this.condition,
    required this.ifPrefill,
    required this.elsePrefill,
  });

  /// Text of the block's `if` tag, which says which value of the variable is
  /// true.
  final String condition;

  final String ifPrefill;
  final String elsePrefill;
}
