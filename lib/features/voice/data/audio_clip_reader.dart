import 'dart:io';
import 'dart:typed_data';

/// A clip read into the shape the speech engines take.
class AudioClip {
  const AudioClip({required this.samples, required this.sampleRate});

  /// Mono samples in the range -1 to 1. A clip with more than one channel is
  /// averaged down to one, because that is what the engines hear.
  final Float32List samples;

  /// The rate the clip was captured at. The engines resample from here rather
  /// than the app converting first, so nothing is decoded twice.
  final int sampleRate;

  bool get isEmpty => samples.isEmpty || sampleRate <= 0;
}

/// Reads [path] as a WAV file.
///
/// **Why this exists.** The native reader this engine used before
/// (`sherpa.readWave`) insists the `fmt ` subchunk is exactly 16 bytes. macOS
/// writes every recording this app makes as **WAVE_FORMAT_EXTENSIBLE** — a
/// 40-byte `fmt ` plus `JUNK` and `FLLR` chunks, 4096 bytes of header before the
/// samples — so the native reader returned an empty wave and said why only on
/// stderr (`wave-reader.cc: ReadWaveImpl: Expected subchunk1_size 16. Given:
/// 40`). Transcribing a real recording then failed with "the clip could not be
/// read as audio" while the clip held perfectly good speech, and no test
/// noticed because the device test decoded a clip `say` synthesized, whose
/// header is the canonical 44-byte form.
///
/// Reading the file here costs nothing and covers what a recorder may
/// legitimately write: the extensible header, 8/16/24/32-bit integer samples,
/// 32/64-bit float samples, more than one channel, unknown chunks in any
/// order, odd-sized chunks, and a `data` size that was never finalized.
AudioClip readAudioClip(String path) {
  final bytes = File(path).readAsBytesSync();
  if (bytes.length < 12 ||
      _tagAt(bytes, 0) != 'RIFF' ||
      _tagAt(bytes, 8) != 'WAVE') {
    throw StateError('That file is not a WAV clip the transcriber can read.');
  }

  var format = 0;
  var channels = 0;
  var sampleRate = 0;
  var bits = 0;
  var dataOffset = -1;
  var dataSize = 0;

  var offset = 12;
  while (offset + 8 <= bytes.length && dataOffset < 0) {
    final id = _tagAt(bytes, offset);
    final size = _uint32At(bytes, offset + 4);
    final body = offset + 8;

    switch (id) {
      case 'fmt ':
        if (size < 16 || body + 16 > bytes.length) {
          throw StateError(
            'That clip has a WAV header the transcriber cannot read.',
          );
        }
        format = _uint16At(bytes, body);
        channels = _uint16At(bytes, body + 2);
        sampleRate = _uint32At(bytes, body + 4);
        bits = _uint16At(bytes, body + 14);
        // 0xFFFE is the extensible header: the real format is the first two
        // bytes of the sub-format GUID after the 16 basic bytes.
        if (format == 0xFFFE && size >= 40 && body + 26 <= bytes.length) {
          format = _uint16At(bytes, body + 24);
        }
      case 'data':
        dataOffset = body;
        // A recorder that has not finalized the file writes no size, and a
        // captured file may be shorter than its header claims: what is in the
        // file is the truth either way.
        final available = bytes.length - body;
        dataSize = (size == 0 || size > available) ? available : size;
    }

    // The next chunk starts after this one, padded to an even offset.
    offset = body + size + (size & 1);
  }

  if (dataOffset < 0) {
    throw StateError('That clip holds no audio.');
  }
  if (channels <= 0 || sampleRate <= 0 || bits <= 0) {
    throw StateError("That clip's WAV header does not describe any audio.");
  }

  final bytesPerSample = bits ~/ 8;
  final frameSize = bytesPerSample * channels;
  final frames = frameSize > 0 ? dataSize ~/ frameSize : 0;
  if (frames <= 0) {
    throw StateError('That clip holds no audio.');
  }

  const little = Endian.little;
  final view = ByteData.sublistView(bytes);
  final samples = Float32List(frames);
  var position = dataOffset;

  for (var frame = 0; frame < frames; frame++) {
    var sum = 0.0;
    for (var channel = 0; channel < channels; channel++) {
      sum += _sampleAt(view, position, format, bits, little);
      position += bytesPerSample;
    }
    samples[frame] = sum / channels;
  }

  return AudioClip(samples: samples, sampleRate: sampleRate);
}

/// One sample, normalized to -1..1.
///
/// [format] is the WAV format tag (1 is integer PCM, 3 is IEEE float), already
/// resolved through the extensible header when it was one.
double _sampleAt(
  ByteData view,
  int offset,
  int format,
  int bits,
  Endian endian,
) {
  if (format == 1) {
    switch (bits) {
      case 8:
        // Eight-bit WAV is unsigned, and 128 is silence.
        return (view.getUint8(offset) - 128) / 128;
      case 16:
        return view.getInt16(offset, endian) / 32768;
      case 24:
        final value =
            view.getUint8(offset) |
            (view.getUint8(offset + 1) << 8) |
            (view.getUint8(offset + 2) << 16);
        // Sign-extend the 24-bit value before scaling it.
        final signed = value >= 0x800000 ? value - 0x1000000 : value;
        return signed / 8388608;
      case 32:
        return view.getInt32(offset, endian) / 2147483648;
    }
  }
  if (format == 3) {
    switch (bits) {
      case 32:
        return view.getFloat32(offset, endian);
      case 64:
        return view.getFloat64(offset, endian);
    }
  }
  throw StateError(
    'That clip uses an audio format the transcriber cannot read '
    '($bits-bit, format $format).',
  );
}

String _tagAt(Uint8List bytes, int offset) =>
    String.fromCharCodes(bytes, offset, offset + 4);

int _uint16At(Uint8List bytes, int offset) =>
    bytes[offset] | (bytes[offset + 1] << 8);

int _uint32At(Uint8List bytes, int offset) =>
    bytes[offset] |
    (bytes[offset + 1] << 8) |
    (bytes[offset + 2] << 16) |
    (bytes[offset + 3] << 24);
