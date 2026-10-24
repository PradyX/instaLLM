import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:installm/features/voice/domain/speech_voice.dart';
import 'package:installm/storage/secure_storage.dart';

/// Which engine turns speech into text in the composer.
enum SttEngine {
  /// Legacy GGUF engine, retained for internal transcription compatibility.
  /// Saved choices now resolve to [whisper]; Settings no longer offers it.
  localModel('localModel'),

  /// The operating system's recognizer. Lightweight, but on some setups
  /// the audio may be processed on the vendor's servers.
  platform('platform'),

  /// Whisper on this device through sherpa-onnx. Fully offline, with its own
  /// ONNX speech model downloaded from Settings.
  whisper('whisper');

  const SttEngine(this.key);

  /// Storage key; legacy, missing and unknown values read back as [whisper].
  final String key;

  static SttEngine fromKey(Object? key) {
    for (final engine in SttEngine.values) {
      if (engine.key == key && engine != SttEngine.localModel) return engine;
    }
    return SttEngine.whisper;
  }
}

/// Which GGUF models and voices the user chose for voice work.
///
/// Only the choices live here: model files remain owned by the model
/// selection store, platform voices belong to the operating system, and
/// nothing is downloaded by picking either of them.
class VoiceSettingsState {
  const VoiceSettingsState({
    this.sttModelId,
    this.sttEngine = SttEngine.whisper,
    this.whisperModelId,
    this.ttsVoiceId,
    this.ttsRate,
    this.readRepliesAloud = false,
  });

  /// Model that transcribes local audio, or null when none is chosen.
  final String? sttModelId;

  /// Engine the composer mic uses. Whisper is the default because it
  /// never sends audio anywhere.
  final SttEngine sttEngine;

  /// Whisper model the Whisper engine runs, or null when none is chosen.
  ///
  /// Stored as an id rather than a path: a model that was removed resolves to
  /// nothing, and the engine then falls back to whatever else is installed
  /// instead of pointing at a file that is gone.
  final String? whisperModelId;

  /// Voice used for reading text aloud, as `name|locale`, or null for the
  /// device default. Stored as text so a voice that is no longer installed
  /// simply resolves to nothing instead of breaking the settings.
  final String? ttsVoiceId;

  /// Speaking rate, or null when the user never changed it.
  final double? ttsRate;

  /// Whether a finished reply is read out on its own. Off by default: speech
  /// is something the user turns on, never something the app decides to do.
  final bool readRepliesAloud;

  bool get hasSttModel => sttModelId != null && sttModelId!.trim().isNotEmpty;

  bool get hasCustomTtsVoice =>
      ttsVoiceId != null && ttsVoiceId!.trim().isNotEmpty;
  VoiceSettingsState copyWith({
    Object? sttModelId = _unset,
    SttEngine? sttEngine,
    Object? whisperModelId = _unset,
    Object? ttsVoiceId = _unset,
    Object? ttsRate = _unset,
    bool? readRepliesAloud,
  }) {
    return VoiceSettingsState(
      sttModelId: sttModelId == _unset
          ? this.sttModelId
          : sttModelId as String?,
      sttEngine: sttEngine ?? this.sttEngine,
      whisperModelId: whisperModelId == _unset
          ? this.whisperModelId
          : whisperModelId as String?,
      ttsVoiceId: ttsVoiceId == _unset
          ? this.ttsVoiceId
          : ttsVoiceId as String?,
      ttsRate: ttsRate == _unset ? this.ttsRate : ttsRate as double?,
      readRepliesAloud: readRepliesAloud ?? this.readRepliesAloud,
    );
  }

  static const _unset = Object();
}

final voiceSettingsProvider =
    NotifierProvider<VoiceSettingsNotifier, VoiceSettingsState>(
      VoiceSettingsNotifier.new,
    );

class VoiceSettingsNotifier extends Notifier<VoiceSettingsState> {
  static const _settingsKey = 'voice_settings';
  // V2 replaces the old GGUF default with Whisper. Legacy records are resolved
  // on read and written with this version only after an explicit change.
  static const _sttEngineVersion = 2;

  @override
  VoiceSettingsState build() {
    _loadSettings();
    return const VoiceSettingsState();
  }

  Future<void> _loadSettings() async {
    try {
      final data = await SecureStorage.instance.read(_settingsKey);
      if (data == null) return;

      final sttModelId = data['sttModelId'];
      final sttEngine = SttEngine.fromKey(data['sttEngine']);
      final whisperModelId = data['whisperModelId'];
      final ttsVoiceId = data['ttsVoiceId'];
      final ttsRate = data['ttsRate'];
      final ttsRateVersion = data['ttsRateVersion'];
      final readRepliesAloud = data['readRepliesAloud'];
      state = state.copyWith(
        sttModelId: sttModelId is String && sttModelId.trim().isNotEmpty
            ? sttModelId
            : null,
        sttEngine: sttEngine,
        whisperModelId:
            whisperModelId is String && whisperModelId.trim().isNotEmpty
            ? whisperModelId
            : null,
        // Keys added after speech to text existed simply stay unset in a
        // document written by an older build.
        ttsVoiceId: ttsVoiceId is String && ttsVoiceId.trim().isNotEmpty
            ? ttsVoiceId
            : null,
        // A rate written before it became a plain multiplier (0.5 was normal
        // speed) is converted on read. The conversion is idempotent, so a
        // document nobody changes keeps resolving to the same speed, and the
        // version is stored with the next change.
        ttsRate: ttsRate is num
            ? resolveStoredSpeechRate(ttsRate, version: ttsRateVersion)
            : null,
        readRepliesAloud: readRepliesAloud is bool
            ? readRepliesAloud
            : state.readRepliesAloud,
      );
    } catch (_) {
      // Keep defaults if storage read fails.
    }
  }

  /// Chooses which engine the composer mic transcribes with.
  Future<void> setSttEngine(SttEngine engine) async {
    state = state.copyWith(sttEngine: engine);
    await _persist();
  }

  /// Chooses the transcription model, or clears the choice with null.
  Future<void> setSttModel(String? modelId) async {
    final trimmed = modelId?.trim();
    state = state.copyWith(
      sttModelId: trimmed == null || trimmed.isEmpty ? null : trimmed,
    );
    await _persist();
  }

  /// Chooses the Whisper model the Whisper engine runs, or clears it with
  /// null. The file itself is owned by the Whisper model picker.
  Future<void> setWhisperModel(String? modelId) async {
    final trimmed = modelId?.trim();
    state = state.copyWith(
      whisperModelId: trimmed == null || trimmed.isEmpty ? null : trimmed,
    );
    await _persist();
  }

  /// Chooses the voice used to read text aloud, or null for the device one.
  Future<void> setTtsVoiceId(String? voiceId) async {
    final trimmed = voiceId?.trim();
    state = state.copyWith(
      ttsVoiceId: trimmed == null || trimmed.isEmpty ? null : trimmed,
    );
    await _persist();
  }

  /// Stores the speaking rate exactly as given; the caller clamps it.
  Future<void> setTtsRate(double? rate) async {
    state = state.copyWith(ttsRate: rate);
    await _persist();
  }

  /// Turns automatic reading of finished replies on or off.
  Future<void> setReadRepliesAloud(bool value) async {
    state = state.copyWith(readRepliesAloud: value);
    await _persist();
  }

  Future<void> _persist() async {
    await SecureStorage.instance.write(
      key: _settingsKey,
      value: {
        'sttModelId': state.sttModelId,
        'sttEngine': state.sttEngine.key,
        'sttEngineVersion': _sttEngineVersion,
        'whisperModelId': state.whisperModelId,
        'ttsVoiceId': state.ttsVoiceId,
        'ttsRate': state.ttsRate,
        'ttsRateVersion': currentSpeechRateVersion,
        'readRepliesAloud': state.readRepliesAloud,
      },
    );
  }
}
