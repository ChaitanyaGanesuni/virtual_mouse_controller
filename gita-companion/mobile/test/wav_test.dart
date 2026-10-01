import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gita_companion/core/audio/wav.dart';

Uint8List wav({required int sampleRate, required int seconds, int dataSizeField = -1}) {
  const channels = 1, bits = 16;
  final byteRate = sampleRate * channels * bits ~/ 8;
  final data = byteRate * seconds;
  final b = ByteData(44 + data);
  void tag(int at, String s) => s.codeUnits.asMap().forEach((i, c) => b.setUint8(at + i, c));
  tag(0, 'RIFF');
  b.setUint32(4, 36 + data, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  b.setUint32(16, 16, Endian.little);
  b.setUint16(20, 1, Endian.little);
  b.setUint16(22, channels, Endian.little);
  b.setUint32(24, sampleRate, Endian.little);
  b.setUint32(28, byteRate, Endian.little);
  b.setUint16(32, channels * bits ~/ 8, Endian.little);
  b.setUint16(34, bits, Endian.little);
  tag(36, 'data');
  b.setUint32(40, dataSizeField >= 0 ? dataSizeField : data, Endian.little);
  return b.buffer.asUint8List();
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('wav'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('reads the duration from a PCM WAV header', () {
    final f = File('${dir.path}/a.wav')..writeAsBytesSync(wav(sampleRate: 22050, seconds: 3));
    expect(wavDurationSeconds(f), closeTo(3.0, 1e-9));
  });

  test('falls back to the file length when the data size is unset', () {
    final f = File('${dir.path}/b.wav')
      ..writeAsBytesSync(wav(sampleRate: 16000, seconds: 2, dataSizeField: 0));
    expect(wavDurationSeconds(f), closeTo(2.0, 1e-9));
  });

  test('non-WAV files give null', () {
    final f = File('${dir.path}/c.wav')..writeAsStringSync('not audio' * 10);
    expect(wavDurationSeconds(f), isNull);
    expect(wavDurationSeconds(File('${dir.path}/missing.wav')), isNull);
  });
}
