/// Dart port of `gita_content/romanize.py::loose()`. Folds IAST and informal
/// spellings ("phaleshu", "kadachana", "krishna") into one ASCII form used
/// only for matching. Must produce exactly the outputs in
/// content/tests/romanize_vectors.json (checked by test/romanize_test.dart).
library;

const _iast = [
  ('ch', '\u0001'), // IAST 'ch' (छ) protected before 'c' is expanded
  ('c', 'ch'),
  ('\u0001', 'ch'),
  ('ś', 's'), ('ṣ', 's'),
  ('ṝ', 'ri'), ('ṛ', 'ri'), ('ḹ', 'li'), ('ḷ', 'li'),
  ('ṅ', 'n'), ('ñ', 'n'), ('ṇ', 'n'), ('ṃ', 'm'), ('ṁ', 'm'), ('ḥ', 'h'),
];

const _informal = [
  ('chh', 'ch'),
  ('sh', 's'),
  ('x', 'ks'),
  ('w', 'v'),
  ('ee', 'i'),
  ('oo', 'u'),
  ('aa', 'a'),
  ('ii', 'i'),
  ('uu', 'u'),
];

/// Remaining precomposed letters with diacritics, folded to their base
/// letter (Python does this with NFKD + dropping combining marks).
const _strip = {
  'ā': 'a',
  'á': 'a',
  'à': 'a',
  'â': 'a',
  'ä': 'a',
  'ã': 'a',
  'ī': 'i',
  'í': 'i',
  'ì': 'i',
  'î': 'i',
  'ï': 'i',
  'ū': 'u',
  'ú': 'u',
  'ù': 'u',
  'û': 'u',
  'ü': 'u',
  'ē': 'e',
  'é': 'e',
  'è': 'e',
  'ê': 'e',
  'ë': 'e',
  'ō': 'o',
  'ó': 'o',
  'ò': 'o',
  'ô': 'o',
  'ö': 'o',
  'ṭ': 't',
  'ḍ': 'd',
  'ṟ': 'r',
  'ḻ': 'l',
  'ẏ': 'y',
  'ç': 'c',
};

final _combining = RegExp('[̀-ͯ]');
final _apostrophes = RegExp("['’ऽ]");
final _nonAlnum = RegExp('[^a-z0-9]+');

String loose(String text) {
  var s = text.toLowerCase();
  for (final (a, b) in _iast) {
    s = s.replaceAll(a, b);
  }
  s = s.split('').map((ch) => _strip[ch] ?? ch).join().replaceAll(_combining, '');
  s = s.replaceAll(_apostrophes, '').replaceAll(_nonAlnum, ' ');
  for (final (a, b) in _informal) {
    s = s.replaceAll(a, b);
  }
  return s.split(' ').where((w) => w.isNotEmpty).join(' ');
}
