class LlmPromptMessage {
  final bool isUser;
  final String text;

  /// Images attached to this message, in the order they were added.
  final List<String> imagePaths;

  const LlmPromptMessage.user(this.text, {this.imagePaths = const []})
    : isUser = true;
  const LlmPromptMessage.assistant(this.text)
    : isUser = false,
      imagePaths = const [];

  /// Paths that actually point at an image, in order.
  List<String> get usableImagePaths => [
    for (final path in imagePaths)
      if (path.trim().isNotEmpty) path,
  ];
}

class BuiltLlmPrompt {
  final String prompt;
  final List<String> imagePaths;

  const BuiltLlmPrompt({required this.prompt, this.imagePaths = const []});
}

String buildLlmChatPrompt(
  List<LlmPromptMessage> messages, {
  String systemPrompt = 'You are a helpful and concise assistant.',
  String assistantPrefill = '',
}) {
  final promptBuffer = StringBuffer();
  promptBuffer.writeln('<|im_start|>system\n$systemPrompt<|im_end|>');

  for (final message in messages) {
    final role = message.isUser ? 'user' : 'assistant';
    promptBuffer.writeln('<|im_start|>$role\n${message.text}<|im_end|>');
  }

  promptBuffer.write('<|im_start|>assistant\n$assistantPrefill');
  return promptBuffer.toString();
}

/// Builds the prompt for [promptFormatId], with [assistantPrefill] written
/// where the model's own reply begins.
///
/// The prefill is what a model's own chat template appends there — today the
/// empty, already-closed thought block a thinking template emits when the user
/// asks for an answer instead of a deliberation (the model's declared
/// reasoning). Writing
/// it is how a reasoning choice reaches the model without rendering its Jinja
/// template: the app builds the prompt itself, so the template's own text for
/// that state is what it inserts. The gemma3 branch ignores it, because the
/// templates that declare a reasoning control are chatml-shaped.
/// The prompt format a model's own GGUF chat template declares.
///
/// Read from `tokenizer.chat_template` instead of a model's name or the
/// repository it came from: the template is what the file was trained to see,
/// and one repository can ship several. A missing or blank template means the
/// file declares no instruction format at all — a base completion model, which
/// no amount of formatting turns into a chat assistant — and is reported as
/// `null` so callers can say so instead of guessing.
String? promptFormatFromTemplate(String? template) {
  final text = template?.trim();
  if (text == null || text.isEmpty) return null;
  final lower = text.toLowerCase();
  if (lower.contains('[inst]')) return 'llama2';
  if (lower.contains('### instruction')) return 'alpaca';
  if (lower.contains('<|start_header_id|>')) return 'llama3';
  // `<|user|>` is shared by two families: Phi-3 closes a turn with `<|end|>`,
  // Zephyr (which TinyLlama Chat and many 2023 fine-tunes use) with `</s>`.
  if (lower.contains('<|user|>')) {
    return lower.contains('<|end|>') ? 'phi3' : 'zephyr';
  }
  if (lower.contains('<start_of_turn>')) return 'gemma';
  if (lower.contains('<|im_start|>')) return 'chatml';
  // A template exists but is none of the shapes the app builds by hand. ChatML
  // is the closest thing to a common denominator, so it is still better than
  // sending a bare prompt.
  return 'chatml';
}

/// Whether [promptFormatId] is a chat format the app builds itself.
///
/// A recorded format is only a fallback: when a file carries its own template,
/// that template decides.
bool isKnownPromptFormat(String promptFormatId) => const {
  'chatml',
  'gemma3',
  'gemma',
  'llama2',
  'llama3',
  'alpaca',
  'phi3',
  'zephyr',
}.contains(promptFormatId);

BuiltLlmPrompt buildModelChatPrompt(
  List<LlmPromptMessage> messages, {
  String systemPrompt = 'You are a helpful and concise assistant.',
  String promptFormatId = 'chatml',
  String assistantPrefill = '',
}) {
  switch (promptFormatId) {
    case 'gemma3':
      return _buildGemma3Prompt(messages, systemPrompt: systemPrompt);
    case 'gemma':
      return _buildGemmaPrompt(messages, systemPrompt: systemPrompt);
    case 'llama2':
      return _buildLlama2Prompt(
        messages,
        systemPrompt: systemPrompt,
        assistantPrefill: assistantPrefill,
      );
    case 'llama3':
      return _buildLlama3Prompt(
        messages,
        systemPrompt: systemPrompt,
        assistantPrefill: assistantPrefill,
      );
    case 'alpaca':
      return _buildAlpacaPrompt(
        messages,
        systemPrompt: systemPrompt,
        assistantPrefill: assistantPrefill,
      );
    case 'phi3':
      return _buildPhi3Prompt(
        messages,
        systemPrompt: systemPrompt,
        assistantPrefill: assistantPrefill,
      );
    case 'zephyr':
      return _buildZephyrPrompt(
        messages,
        systemPrompt: systemPrompt,
        assistantPrefill: assistantPrefill,
      );
    default:
      return BuiltLlmPrompt(
        prompt: buildLlmChatPrompt(
          messages,
          systemPrompt: systemPrompt,
          assistantPrefill: assistantPrefill,
        ),
      );
  }
}

String modelStopToken(String promptFormatId) {
  return switch (promptFormatId) {
    'gemma3' || 'gemma' => '<end_of_turn>',
    'llama2' || 'alpaca' => '</s>',
    'llama3' => '<|eot_id|>',
    'phi3' => '<|end|>',
    'zephyr' => '</s>',
    _ => '<|im_end|>',
  };
}

BuiltLlmPrompt _buildLlama2Prompt(
  List<LlmPromptMessage> messages, {
  required String systemPrompt,
  required String assistantPrefill,
}) {
  final promptBuffer = StringBuffer();
  final system = systemPrompt.trim();
  var openedInstruction = false;

  for (final message in messages) {
    if (message.isUser) {
      if (!openedInstruction && system.isNotEmpty) {
        promptBuffer.write('[INST] <<SYS>>\n$system\n<</SYS>>\n\n');
        openedInstruction = true;
      } else {
        promptBuffer.write('[INST] ');
        openedInstruction = true;
      }
      promptBuffer.write('${message.text.trim()} [/INST]');
      continue;
    }
    promptBuffer.write(' ${message.text.trim()} </s>');
  }

  if (!openedInstruction) {
    promptBuffer.write('[INST] ${system.isEmpty ? '' : '$system '}[/INST]');
  }
  promptBuffer.write(assistantPrefill.isEmpty ? '' : ' $assistantPrefill');

  return BuiltLlmPrompt(prompt: promptBuffer.toString());
}

BuiltLlmPrompt _buildLlama3Prompt(
  List<LlmPromptMessage> messages, {
  required String systemPrompt,
  required String assistantPrefill,
}) {
  final promptBuffer = StringBuffer();
  final imagePaths = <String>[];
  final system = systemPrompt.trim();

  void writeTurn(String role, String body) {
    promptBuffer.write(
      '<|start_header_id|>$role<|end_header_id|>\n\n$body<|eot_id|>',
    );
  }

  if (system.isNotEmpty) writeTurn('system', system);
  for (final message in messages) {
    if (message.isUser) {
      imagePaths.addAll(message.usableImagePaths);
      writeTurn('user', message.text.trim());
      continue;
    }
    writeTurn('assistant', message.text.trim());
  }
  promptBuffer.write(
    '<|start_header_id|>assistant<|end_header_id|>\n\n$assistantPrefill',
  );

  return BuiltLlmPrompt(
    prompt: promptBuffer.toString(),
    imagePaths: imagePaths,
  );
}

BuiltLlmPrompt _buildAlpacaPrompt(
  List<LlmPromptMessage> messages, {
  required String systemPrompt,
  required String assistantPrefill,
}) {
  final promptBuffer = StringBuffer();
  promptBuffer.writeln(
    'Below is an instruction that describes a task. Write a response that '
    'appropriately completes the request.',
  );
  final system = systemPrompt.trim();
  if (system.isNotEmpty) {
    promptBuffer
      ..writeln()
      ..writeln(system);
  }

  for (final message in messages) {
    promptBuffer
      ..writeln()
      ..writeln(message.isUser ? '### Instruction:' : '### Response:')
      ..writeln(message.text.trim());
  }
  promptBuffer
    ..writeln()
    ..writeln('### Response:')
    ..write(assistantPrefill);

  return BuiltLlmPrompt(prompt: promptBuffer.toString());
}

BuiltLlmPrompt _buildPhi3Prompt(
  List<LlmPromptMessage> messages, {
  required String systemPrompt,
  required String assistantPrefill,
}) {
  final promptBuffer = StringBuffer();
  final system = systemPrompt.trim();
  if (system.isNotEmpty) {
    promptBuffer.write('<|system|>\n$system<|end|>\n');
  }
  for (final message in messages) {
    promptBuffer.write(
      message.isUser
          ? '<|user|>\n${message.text.trim()}<|end|>\n'
          : '<|assistant|>\n${message.text.trim()}<|end|>\n',
    );
  }
  promptBuffer.write('<|assistant|>\n$assistantPrefill');

  return BuiltLlmPrompt(prompt: promptBuffer.toString());
}

/// Zephyr and the fine-tunes built on it (TinyLlama Chat among them):
/// `<|role|>` markers with every turn closed by the end-of-sequence token.
BuiltLlmPrompt _buildZephyrPrompt(
  List<LlmPromptMessage> messages, {
  required String systemPrompt,
  required String assistantPrefill,
}) {
  final promptBuffer = StringBuffer();
  final system = systemPrompt.trim();
  if (system.isNotEmpty) {
    promptBuffer.write('<|system|>\n$system</s>\n');
  }
  for (final message in messages) {
    promptBuffer.write(
      message.isUser
          ? '<|user|>\n${message.text.trim()}</s>\n'
          : '<|assistant|>\n${message.text.trim()}</s>\n',
    );
  }
  promptBuffer.write('<|assistant|>\n$assistantPrefill');

  return BuiltLlmPrompt(prompt: promptBuffer.toString());
}

/// Gemma 2 and older: no vision markers, so images are ignored the way the
/// model itself ignores them.
BuiltLlmPrompt _buildGemmaPrompt(
  List<LlmPromptMessage> messages, {
  required String systemPrompt,
}) {
  final promptBuffer = StringBuffer();
  final system = systemPrompt.trim();

  if (system.isNotEmpty) {
    promptBuffer
      ..write('<start_of_turn>user\n')
      ..write('System: $system\n')
      ..write('<end_of_turn>\n');
  }

  for (final message in messages) {
    promptBuffer
      ..write(
        message.isUser ? '<start_of_turn>user\n' : '<start_of_turn>model\n',
      )
      ..write('${message.text.trim()}\n')
      ..write('<end_of_turn>\n');
  }

  promptBuffer.write('<start_of_turn>model\n');
  return BuiltLlmPrompt(prompt: promptBuffer.toString());
}

BuiltLlmPrompt _buildGemma3Prompt(
  List<LlmPromptMessage> messages, {
  required String systemPrompt,
}) {
  final promptBuffer = StringBuffer();
  final imagePaths = <String>[];

  if (systemPrompt.trim().isNotEmpty) {
    promptBuffer
      ..write('<start_of_turn>user\n')
      ..write('System: ${systemPrompt.trim()}\n')
      ..write('<end_of_turn>\n');
  }

  for (final message in messages) {
    if (message.isUser) {
      promptBuffer.write('<start_of_turn>user\n');
      // One marker per image, in attachment order, so the model sees the same
      // order the message records.
      for (final imagePath in message.usableImagePaths) {
        promptBuffer.write('<image>\n');
        imagePaths.add(imagePath);
      }
      if (message.text.trim().isNotEmpty) {
        promptBuffer.write('${message.text.trim()}\n');
      }
      promptBuffer.write('<end_of_turn>\n');
      continue;
    }

    promptBuffer
      ..write('<start_of_turn>model\n')
      ..write('${message.text.trim()}\n')
      ..write('<end_of_turn>\n');
  }

  promptBuffer.write('<start_of_turn>model\n');

  return BuiltLlmPrompt(
    prompt: promptBuffer.toString(),
    imagePaths: imagePaths,
  );
}

/// A complete thought block, with or without the `>` a model may leave out.
///
/// Thinking templates wrap the thought in `<think>` and `</think>`, but the
/// opening tag also arrives bare (`<think`) from models that repeat the
/// template's prefill, and a run that was stopped mid-thought never closes the
/// block at all. All of it is the model talking to itself, never the answer.
final RegExp _thoughtBlock = RegExp(r'<think\s*>?[\s\S]*?</think\s*>?');

/// A thought tag left over once its block is gone.
final RegExp _strayThoughtTags = RegExp(r'</?think\s*>?');

/// [raw] without its thought blocks; an unclosed thought ends the text.
String _withoutThoughts(String raw) {
  final closed = raw.replaceAll(_thoughtBlock, '');
  final unclosed = closed.indexOf('<think');
  return unclosed < 0 ? closed : closed.substring(0, unclosed);
}

String buildStreamingResponseText(String raw) {
  if (raw.isEmpty) return '';

  final thinkStart = raw.indexOf('<think');
  if (thinkStart == -1) return raw;

  var thinkContentStart = thinkStart + '<think'.length;
  if (thinkContentStart < raw.length && raw[thinkContentStart] == '>') {
    thinkContentStart++;
  }

  final thinkEnd = raw.indexOf('</think', thinkContentStart);

  if (thinkEnd == -1) {
    final thinking = raw.substring(thinkContentStart).trimLeft();
    if (thinking.isEmpty) return 'Thinking...';
    return 'Thinking...\n$thinking';
  }

  final thinking = raw.substring(thinkContentStart, thinkEnd).trim();
  final rawAnswer = raw.substring(thinkEnd + '</think'.length).trimLeft();
  final answer = rawAnswer.startsWith('>')
      ? rawAnswer.substring(1).trimLeft()
      : rawAnswer;

  if (answer.isEmpty) {
    return thinking.isEmpty ? 'Thinking...' : 'Thinking...\n$thinking';
  }

  if (thinking.isEmpty) return answer;
  return 'Thinking...\n$thinking\n\n$answer';
}

/// The answer in [raw]: the thought block and any stray tag removed.
String buildFinalResponseText(String raw) {
  final answer = _withoutThoughts(raw).replaceAll(_strayThoughtTags, '').trim();
  return answer.isEmpty ? 'No response generated.' : answer;
}

/// What a voice should read from [text]: the answer, never the thought.
///
/// The chat shows `Thinking...` followed by the thought while a run is still
/// going, so a reply captured mid-thought returns nothing rather than reading
/// the model's notes aloud. A finished reply holds only its answer.
String spokenReplyText(String text) {
  final trimmed = text.trim();
  if (trimmed.startsWith('Thinking...')) return '';
  return _withoutThoughts(trimmed).replaceAll(_strayThoughtTags, '').trim();
}

/// [systemPrompt] with the device's current local date and time.
///
/// A local model has no clock of its own: nothing in a conversation tells it
/// what day it is unless the prompt does, so every request carries the date the
/// phone or computer reports. [now] is a seam for tests.
String withCurrentDateTime(String systemPrompt, {DateTime? now}) {
  final local = (now ?? DateTime.now()).toLocal();
  final time =
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
  final stamp =
      '${_weekdays[local.weekday - 1]}, ${local.day} '
      '${_months[local.month - 1]} ${local.year} at $time';
  final base = systemPrompt.trim();
  final fact = 'Current date and time (device local time): $stamp.';
  return base.isEmpty ? fact : '$base\n\n$fact';
}

const List<String> _weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

const List<String> _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];
