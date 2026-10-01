import pytest

from gita_content.romanize import loose
from gita_content.transliterate import transliterate

VERSE = "कर्मण्येवाधिकारस्ते मा फलेषु कदाचन ।\nमा कर्मफलहेतुर्भूर्मा ते सङ्गोऽस्त्वकर्मणि ॥"


def test_iast():
    assert transliterate(VERSE, "sa-Latn") == (
        "karmaṇyevādhikāraste mā phaleṣu kadācana ।\nmā karmaphalaheturbhūrmā te saṅgo'stvakarmaṇi ॥"
    )


def test_telugu_script():
    assert transliterate(VERSE, "sa-Telu") == ("కర్మణ్యేవాధికారస్తే మా ఫలేషు కదాచన ।\nమా కర్మఫలహేతుర్భూర్మా తే సఙ్గోఽస్త్వకర్మణి ॥")


def test_devanagari_is_identity():
    assert transliterate(VERSE, "sa") == VERSE


# Shared test vectors: the mobile app's port of loose() must pass these too.
@pytest.mark.parametrize(
    "typed,iast",
    [
        ("phaleshu", "phaleṣu"),
        ("phalesu", "phaleṣu"),
        ("kadachana", "kadācana"),
        ("krishna", "kṛṣṇa"),
        ("dharmakshetre", "dharmakṣetre"),
        ("shloka", "śloka"),
        ("sankhya", "sāṅkhya"),
        ("icchami", "icchāmi"),
        ("ichchhami", "icchāmi"),
        ("yogasthah", "yogasthaḥ"),
        ("Vishwaroopa", "viśvarūpa"),
    ],
)
def test_loose_matches_informal_spellings(typed, iast):
    assert loose(typed) == loose(iast)


def test_known_limitation_bare_stripped_r_vowel():
    # ṛ folds to "ri" so that the common spelling "krishna" matches kṛṣṇa.
    # The rarer diacritic-stripped spelling "krsna" therefore does not match.
    # Folding "ri" to "r" everywhere would fix it but would also merge words
    # like hari/har, so this is an accepted limitation.
    assert loose("krsna") != loose("kṛṣṇa")


def test_loose_output_is_ascii_words():
    out = loose("saṅgo'stvakarmaṇi ॥ mā")
    assert out == "sangostvakarmani ma"


def test_shared_vectors_file_matches_python_implementation():
    import json
    from pathlib import Path

    data = json.loads((Path(__file__).parent / "romanize_vectors.json").read_text(encoding="utf-8"))
    for v in data["vectors"]:
        assert loose(v["input"]) == v["loose"], v["input"]
