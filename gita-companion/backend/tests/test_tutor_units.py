"""Pure functions of the tutor: reference parsing, quote matching, safety."""

from app.modules.ai_tutor.refs import chapter_refs, verse_refs
from app.modules.ai_tutor.safety import support_note
from app.modules.ai_tutor.validate import quote_matches, unquote_unverified


def ids(text):
    return [r.id for r in verse_refs(text)]


def test_verse_refs():
    assert ids("BG 2.47 and (18.66).") == ["2.47", "18.66"]
    assert ids("see 2:47") == ["2.47"]
    assert ids("verses 2.47-49") == ["2.47", "2.48", "2.49"]
    assert ids("8.5–8.6") == ["8.5", "8.6"]
    assert ids("chapter 2, verse 47 and chapter 3 verse 19") == ["2.47", "3.19"]
    assert ids("అధ్యాయం 2, శ్లోకం 47") == ["2.47"]
    # Not references: longer numbers, versions.
    assert ids("1.234 and 10.5.3") == []
    # Reported as written, even when the verse does not exist (the validator decides).
    assert ids("BG 2.99") == ["2.99"]
    # A huge range is not expanded.
    assert ids("2.1-70") == ["2.1"]


def test_chapter_refs():
    assert chapter_refs("Chapter 3 and chapter 12") == [3, 12]
    assert chapter_refs("chapter 2, verse 47") == []
    assert chapter_refs("అధ్యాయం 18 లో") == [18]


def test_quote_matching_is_tolerant_of_punctuation_and_small_slips():
    src = ["karmaṇyevādhikāraste mā phaleṣu kadācana ।\nmā karmaphalaheturbhūrmā te saṅgo'stvakarmaṇi ॥"]
    assert quote_matches("mā phaleṣu kadācana", src)
    assert quote_matches("karmaṇyevādhikāraste mā phaleṣu kadacana", src)  # one missing diacritic
    assert not quote_matches("you have a right to the fruits", src)


def test_unquote_keeps_short_terms():
    text, n = unquote_unverified('The word "dharma" and "an invented saying of the Lord".', ["nothing"])
    assert n == 1 and '"dharma"' in text and "an invented saying of the Lord" in text and '"an' not in text


def test_support_note():
    assert support_note("I want to end my life", "en")
    assert "14416" in support_note("నాకు ఆత్మహత్య ఆలోచనలు", "te")
    assert support_note("How do I do my duty?", "en") is None
    assert support_note("Arjuna does not want to kill his teachers", "en") is None
