import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gita_companion/core/search/romanize.dart';

void main() {
  test('Dart loose() matches the shared Python vectors exactly', () {
    final data =
        jsonDecode(File('../content/tests/romanize_vectors.json').readAsStringSync()) as Map<String, dynamic>;
    final vectors = (data['vectors'] as List).cast<Map<String, dynamic>>();
    expect(vectors, isNotEmpty);
    for (final v in vectors) {
      expect(loose(v['input'] as String), v['loose'], reason: 'input: ${v['input']}');
    }
  });
}
