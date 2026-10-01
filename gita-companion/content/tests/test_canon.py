import pytest

from gita_content.canon import EDITION_701, InvalidVerseRef, VerseRef

STANDARD_COUNTS = [47, 72, 43, 42, 29, 47, 30, 28, 34, 42, 55, 20, 34, 27, 20, 24, 28, 78]


def test_standard_verse_counts(canon):
    assert [canon.chapters[n].verse_count for n in range(1, 19)] == STANDARD_COUNTS
    assert canon.total_verses == 700
    assert len(canon.all_refs(include_extra=False)) == 700
    assert len(canon.all_refs()) == 701


def test_chapter_names(canon):
    # Chapter 2 is Sāṅkhya Yoga and chapter 3 is Karma Yoga (not the other way round).
    assert canon.chapters[2].name_sa == "साङ्ख्ययोग"
    assert canon.chapters[3].name_sa == "कर्मयोग"


@pytest.mark.parametrize(
    "text,expected",
    [("2.47", "2.47"), ("BG 2:47", "2.47"), ("bg2.47", "2.47"), ("18-78", "18.78"), (" 1 1 ", "1.1")],
)
def test_parse(canon, text, expected):
    assert canon.parse(text).id == expected


@pytest.mark.parametrize("text", ["2.73", "19.1", "0.1", "1.0", "13.35", "18.79", "two.47", "2"])
def test_rejects_nonexistent_verses(canon, text):
    with pytest.raises(InvalidVerseRef):
        canon.parse(text)


def test_extra_verse_13_0(canon):
    ref = canon.resolve(13, 0)
    assert not canon.is_canonical(ref)
    assert canon.is_canonical(VerseRef(13, 1))


def test_701_edition_mapping(canon):
    assert canon.resolve(13, 1, EDITION_701).id == "13.0"
    assert canon.resolve(13, 2, EDITION_701).id == "13.1"
    assert canon.resolve(13, 35, EDITION_701).id == "13.34"
    assert canon.resolve(2, 47, EDITION_701).id == "2.47"
    with pytest.raises(InvalidVerseRef):
        canon.resolve(13, 36, EDITION_701)
