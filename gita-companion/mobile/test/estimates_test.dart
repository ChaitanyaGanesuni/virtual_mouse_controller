import 'package:flutter_test/flutter_test.dart';
import 'package:gita_companion/core/content/estimates.dart';
import 'package:gita_companion/core/content/models.dart';

import 'support/pack.dart';

void main() {
  test('syllable count of an anuṣṭubh verse is 32', () {
    final repo = openRealRepository();
    // 2.47 is an anuṣṭubh verse: four pādas of eight syllables.
    expect(syllables(repo.verse('2.47')!.textIn(VerseScript.iast)), 32);
  });

  test('chapter estimates are plausible', () {
    final repo = openRealRepository();
    final ch2 = estimateChapter(repo.versesOf(2), explanationLanguage: 'en');
    // 72 verses × 20 s ≈ 24 min reading; ~72 × 15 s ≈ 18 min recitation.
    expect(ch2.readingMinutes, inInclusiveRange(20, 30));
    expect(ch2.listeningMinutes, inInclusiveRange(14, 24));
    final ch12 = estimateChapter(repo.versesOf(12), explanationLanguage: 'en');
    expect(ch12.readingMinutes, lessThan(ch2.readingMinutes));
  });
}
