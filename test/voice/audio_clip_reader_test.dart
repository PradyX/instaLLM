import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_llm/features/voice/data/audio_clip_reader.dart';

List<int> _le16(int value) => [value & 0xff, (value >> 8) & 0xff];

List<int> _le32(int value) => [
  value & 0xff,
  (value >> 8) & 0xff,
  (value >> 16) & 0xff,
  (value >> 24) & 0xff,
];

/// A whole chunk, padded to an even length the way RIFF requires.
List<int> _chunk(String id, List<int> body, {int? declaredSize}) => [
  ...id.codeUnits,
  ..._le32(declaredSize ?? body.length),
  ...body,
  if (body.length.isOdd) 0,
];

/// The body of a classic PCM `fmt ` chunk: the shape `say` and most tools
/// write.
List<int> _pcmFmt({int channels = 1, int rate = 16000, int bits = 16}) => [
  ..._le16(1),
  ..._le16(channels),
  ..._le32(rate),
  ..._le32(rate * channels * bits ~/ 8),
  ..._le16(channels * bits ~/ 8),
  ..._le16(bits),
];

/// The body of the `fmt ` chunk macOS writes for this app's own recordings: a
/// **40-byte** WAVE_FORMAT_EXTENSIBLE header whose sub-format GUID is PCM.
///
/// That 40 is exactly what the native reader this app used to call refused
/// (`wave-reader.cc: ReadWaveImpl: Expected subchunk1_size 16. Given: 40`),
/// returning an empty wave — which is why transcribing a real recording failed
/// with "the clip could not be read as audio" while the clip was fine. No audio
/// is included in these fixtures: only headers, never the user's speech.
List<int> _extensibleFmt({
  int channels = 1,
  int rate = 16000,
  int bits = 16,
}) => [
  ..._le16(0xfffe),
  ..._le16(channels),
  ..._le32(rate),
  ..._le32(rate * channels * bits ~/ 8),
  ..._le16(channels * bits ~/ 8),
  ..._le16(bits),
  ..._le16(22), // extension length
  ..._le16(bits), // valid bits a sample
  ..._le32(4), // front-centre speaker
  0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x10, 0x00, //
  0x80, 0x00, 0x00, 0xaa, 0x00, 0x38, 0x9b, 0x71, // KSDATAFORMAT_SUBTYPE_PCM
];

/// A whole WAV file: [chunks] in order, then the samples.
Uint8List _wav(List<List<int>> chunks, List<int> pcm, {int? declaredDataSize}) {
  final body = <int>[
    for (final chunk in chunks) ...chunk,
    ..._chunk('data', pcm, declaredSize: declaredDataSize),
  ];
  return Uint8List.fromList([
    ...'RIFF'.codeUnits,
    ..._le32(4 + body.length),
    ...'WAVE'.codeUnits,
    ...body,
  ]);
}

List<int> _pcm16(List<int> values) => [
  for (final value in values) ..._le16(value & 0xffff),
];

List<int> _float32(double value) =>
    (ByteData(4)..setFloat32(0, value, Endian.little)).buffer.asUint8List();

/// Writes [bytes] to a temp file and reads it back.
AudioClip _read(Uint8List bytes) {
  final directory = Directory.systemTemp.createTempSync('clip_reader');
  addTearDown(() {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });
  final file = File('${directory.path}/clip.wav')..writeAsBytesSync(bytes);
  return readAudioClip(file.path);
}

void main() {
  test('reads the extensible header macOS writes for a recording', () {
    // The recording's real header, then 0, 8192, 16384: silence, a quarter and
    // half scale.
    final clip = _read(
      _wav([
        _chunk('JUNK', List<int>.filled(28, 0)),
        _chunk('fmt ', _extensibleFmt()),
        _chunk('FLLR', List<int>.filled(12, 0)),
      ], _pcm16([0, 8192, 16384])),
    );

    expect(clip.sampleRate, 16000);
    expect(clip.samples, hasLength(3));
    expect(clip.samples[0], closeTo(0, 1e-6));
    expect(clip.samples[1], closeTo(0.25, 1e-4));
    expect(clip.samples[2], closeTo(0.5, 1e-4));
    expect(clip.isEmpty, isFalse);
  });

  test('reads the canonical 44-byte header too', () {
    final clip = _read(
      _wav([_chunk('fmt ', _pcmFmt())], _pcm16([-32768, -16384, 32767])),
    );

    expect(clip.sampleRate, 16000);
    expect(clip.samples, hasLength(3));
    expect(clip.samples[0], closeTo(-1, 1e-6));
    expect(clip.samples[1], closeTo(-0.5, 1e-4));
    expect(clip.samples[2], closeTo(1, 1e-4));
  });

  test(
    'a stereo clip is averaged down to the one channel the engines hear',
    () {
      final clip = _read(
        _wav([
          _chunk('fmt ', _pcmFmt(channels: 2)),
        ], _pcm16([32767, -32768, 16384, 16384])),
      );

      expect(clip.samples, hasLength(2));
      expect(clip.samples[0], closeTo(0, 1e-4));
      expect(clip.samples[1], closeTo(0.5, 1e-4));
    },
  );

  test('reads 8, 24 and 32-bit integer samples', () {
    final eight = _read(
      _wav([_chunk('fmt ', _pcmFmt(bits: 8))], [0, 128, 255]),
    );
    expect(eight.samples[0], closeTo(-1, 1e-6));
    expect(eight.samples[1], closeTo(0, 1e-6));
    expect(eight.samples[2], closeTo(1, 1e-2));

    final twentyFour = _read(
      _wav(
        [_chunk('fmt ', _pcmFmt(bits: 24))],
        [
          0,
          0,
          0x80, // -8388608, full scale
          0,
          0,
          0x40, // 4194304, half scale
          0xff,
          0xff,
          0x7f, // 8388607
        ],
      ),
    );
    expect(twentyFour.samples[0], closeTo(-1, 1e-6));
    expect(twentyFour.samples[1], closeTo(0.5, 1e-4));
    expect(twentyFour.samples[2], closeTo(1, 1e-4));

    final thirtyTwo = _read(
      _wav(
        [_chunk('fmt ', _pcmFmt(bits: 32))],
        [..._le32(2147483648), ..._le32(1073741824)],
      ),
    );
    expect(thirtyTwo.samples[0], closeTo(-1, 1e-6));
    expect(thirtyTwo.samples[1], closeTo(0.5, 1e-4));
  });

  test('reads 32-bit float samples when the header says so', () {
    final clip = _read(
      _wav(
        [
          _chunk('fmt ', [
            ..._le16(3),
            ..._le16(1),
            ..._le32(16000),
            ..._le32(64000),
            ..._le16(4),
            ..._le16(32),
          ]),
        ],
        [..._float32(-0.25), ..._float32(0.75)],
      ),
    );

    expect(clip.samples[0], closeTo(-0.25, 1e-6));
    expect(clip.samples[1], closeTo(0.75, 1e-6));
  });

  test('unknown chunks in any order, of any length, are skipped', () {
    final clip = _read(
      _wav([
        _chunk('LIST', [1, 2, 3]), // odd length: padded by a byte
        _chunk('fmt ', _pcmFmt()),
        _chunk('fact', [4, 0, 0, 0]),
      ], _pcm16([16384])),
    );

    expect(clip.sampleRate, 16000);
    expect(clip.samples, hasLength(1));
    expect(clip.samples[0], closeTo(0.5, 1e-4));
  });

  test('a data size that was never written falls back to the file', () {
    final clip = _read(
      _wav(
        [_chunk('fmt ', _pcmFmt())],
        _pcm16([16384, 0]),
        declaredDataSize: 0,
      ),
    );

    expect(clip.samples, hasLength(2));
    expect(clip.samples[0], closeTo(0.5, 1e-4));
  });

  test('a file that is not WAV, and a WAV with no audio, say so', () {
    expect(
      () => _read(Uint8List.fromList('this is not audio'.codeUnits)),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('not a WAV clip'),
        ),
      ),
    );

    expect(
      () => _read(_wav([_chunk('fmt ', _pcmFmt())], const [])),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('holds no audio'),
        ),
      ),
    );
  });

  test('an audio encoding this app cannot read is named, not guessed at', () {
    // 12-bit PCM is a real WAV format no speech engine here takes.
    expect(
      () =>
          _read(_wav([_chunk('fmt ', _pcmFmt(bits: 12))], [0, 0, 0, 0, 0, 0])),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('12-bit'),
        ),
      ),
    );
  });
}
