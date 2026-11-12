/// The user's Companion preferences: what it is called, whether it is on, and
/// how the wake/pause behaviour will be tuned.
///
/// The wake word and pause auto-stop are not wired yet, so these two numbers are
/// stored and displayed but do not act on anything; keeping them here from the
/// start means the phase that implements them does not need a storage migration.
class CompanionSettings {
  const CompanionSettings({
    this.name = defaultName,
    this.enabled = false,
    this.wakeSensitivity = defaultWakeSensitivity,
    this.silenceTimeout = defaultSilenceTimeout,
  });

  /// What an untouched install calls its companion.
  static const String defaultName = 'Ada';

  static const int minNameLength = 2;
  static const int maxNameLength = 20;

  /// 0..1, where higher means a detection needs less confidence.
  static const double defaultWakeSensitivity = 0.6;

  static const Duration defaultSilenceTimeout = Duration(milliseconds: 1500);
  static const Duration minSilenceTimeout = Duration(milliseconds: 800);
  static const Duration maxSilenceTimeout = Duration(milliseconds: 3000);

  /// How finely the pause length moves; the slider uses the same step.
  static const Duration silenceTimeoutStep = Duration(milliseconds: 100);

  final String name;

  /// Off until the user turns it on, so nothing listens on a fresh install.
  final bool enabled;

  final double wakeSensitivity;

  /// How long a silence ends the spoken turn.
  final Duration silenceTimeout;

  /// What the user says to wake it, e.g. `Hey Ada`.
  String get wakePhrase => 'Hey $name';

  CompanionSettings copyWith({
    String? name,
    bool? enabled,
    double? wakeSensitivity,
    Duration? silenceTimeout,
  }) {
    return CompanionSettings(
      name: name ?? this.name,
      enabled: enabled ?? this.enabled,
      wakeSensitivity: wakeSensitivity ?? this.wakeSensitivity,
      silenceTimeout: silenceTimeout ?? this.silenceTimeout,
    );
  }

  /// Every stored field clamped into the range the app can use.
  ///
  /// A hand-edited or older file therefore cannot leave the screen describing a
  /// pause of zero or a name that is not a name.
  CompanionSettings normalized() {
    final trimmed = name.trim();
    final resolvedName =
        trimmed.length >= minNameLength && trimmed.length <= maxNameLength
        ? trimmed
        : defaultName;
    final sensitivity = wakeSensitivity.isFinite
        ? wakeSensitivity.clamp(0.0, 1.0)
        : defaultWakeSensitivity;
    final rawMs = silenceTimeout.inMilliseconds.clamp(
      minSilenceTimeout.inMilliseconds,
      maxSilenceTimeout.inMilliseconds,
    );
    final step = silenceTimeoutStep.inMilliseconds;
    final stepped = ((rawMs / step).round() * step).clamp(
      minSilenceTimeout.inMilliseconds,
      maxSilenceTimeout.inMilliseconds,
    );

    return CompanionSettings(
      name: resolvedName,
      enabled: enabled,
      wakeSensitivity: sensitivity,
      silenceTimeout: Duration(milliseconds: stepped),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'enabled': enabled,
      'wakeSensitivity': wakeSensitivity,
      'silenceTimeoutMs': silenceTimeout.inMilliseconds,
    };
  }

  /// Reads a stored payload, falling back field by field.
  ///
  /// A document written before a field existed (or one with a wrong type) keeps
  /// every other stored choice instead of resetting the whole companion.
  factory CompanionSettings.fromJson(Map<String, dynamic> json) {
    final name = json['name'];
    final enabled = json['enabled'];
    final sensitivity = json['wakeSensitivity'];
    final silenceMs = json['silenceTimeoutMs'];

    return CompanionSettings(
      name: name is String ? name : defaultName,
      enabled: enabled is bool ? enabled : false,
      wakeSensitivity: sensitivity is num
          ? sensitivity.toDouble()
          : defaultWakeSensitivity,
      silenceTimeout: silenceMs is num
          ? Duration(milliseconds: silenceMs.round())
          : defaultSilenceTimeout,
    ).normalized();
  }

  /// Why [raw] cannot be the name, or null when it can.
  static String? validateName(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return 'Give the Companion a name.';
    if (trimmed.length < minNameLength) {
      return 'Use at least $minNameLength characters.';
    }
    if (trimmed.length > maxNameLength) {
      return 'Keep it to $maxNameLength characters or fewer.';
    }
    return null;
  }

  /// A soft warning for a name a wake engine may not decode cleanly.
  ///
  /// This never blocks the name: pronunciation is the user's call, and the
  /// wake engine is not committed yet.
  static String? nameWarning(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    if (!RegExp(r"^[A-Za-z0-9 '\-]+$").hasMatch(trimmed)) {
      return 'Letters, numbers, spaces and hyphens wake most reliably.';
    }
    return null;
  }
}
