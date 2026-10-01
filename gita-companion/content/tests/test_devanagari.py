import pytest

from gita_content.devanagari import (
    DevanagariError,
    orthographic_key,
    parse_verse,
    repair_legacy_encoding,
    strict_key,
)


def test_gita_json_style():
    raw = "धृतराष्ट्र उवाच\n\nधर्मक्षेत्रे कुरुक्षेत्रे समवेता युयुत्सवः।\n\nमामकाः पाण्डवाश्चैव किमकुर्वत सञ्जय।।1.1।।\n "
    v = parse_verse(raw)
    assert v.speaker == "dhritarashtra"
    assert v.lines == [
        "धर्मक्षेत्रे कुरुक्षेत्रे समवेता युयुत्सवः ।",
        "मामकाः पाण्डवाश्चैव किमकुर्वत सञ्जय ॥",
    ]


def test_vedicscriptures_style_with_devanagari_number():
    raw = "कर्मण्येवाधिकारस्ते मा फलेषु कदाचन |\nमा कर्मफलहेतुर्भूर्मा ते सङ्गोऽस्त्वकर्मणि ||२-४७||"
    v = parse_verse(raw)
    assert v.speaker is None
    assert v.text == "कर्मण्येवाधिकारस्ते मा फलेषु कदाचन ।\nमा कर्मफलहेतुर्भूर्मा ते सङ्गोऽस्त्वकर्मणि ॥"


def test_glued_speaker_line_and_missing_line_break():
    raw = "श्री भगवानुवाचइदं शरीरं कौन्तेय क्षेत्रमित्यभिधीयते।एतद्यो वेत्ति तं प्राहुः क्षेत्रज्ञ इति तद्विदः।।13.2।।"
    v = parse_verse(raw)
    assert v.speaker == "krishna"
    assert v.lines == [
        "इदं शरीरं कौन्तेय क्षेत्रमित्यभिधीयते ।",
        "एतद्यो वेत्ति तं प्राहुः क्षेत्रज्ञ इति तद्विदः ॥",
    ]


def test_verb_uvaca_inside_verse_is_not_a_speaker():
    # 2.10 begins "tam uvāca hṛṣīkeśaḥ" – narration, not a speaker heading.
    raw = "तमुवाच हृषीकेशः प्रहसन्निव भारत।\n\nसेनयोरुभयोर्मध्ये विषीदन्तमिदं वचः।।2.10।।"
    v = parse_verse(raw)
    assert v.speaker is None
    assert v.lines[0].startswith("तमुवाच")


def test_inner_speaker_line():
    raw = "कृपया परयाविष्टो विषीदन्निदमब्रवीत् |\nअर्जुन उवाच |\nदृष्ट्वेमं स्वजनं कृष्ण युयुत्सुं समुपस्थितम् ||१-२८||"
    v = parse_verse(raw)
    assert v.speaker is None
    assert v.inner_speakers == ["arjuna"]
    assert v.lines[1] == "अर्जुन उवाच"


def test_final_danda_is_fixed_and_recorded():
    v = parse_verse("यत्र योगेश्वरः कृष्णो यत्र पार्थो धनुर्धरः।\n\nतत्र श्रीर्विजयो भूतिर्ध्रुवा नीतिर्मतिर्मम।")
    assert v.lines[-1].endswith(" ॥")
    assert v.fixes


@pytest.mark.parametrize(
    "broken,fixed",
    [
        ("निश्िचतं", "निश्चितं"),
        ("भक्ितं", "भक्तिं"),
        ("तपस्तत्ित्रविधं", "तपस्तत्त्रिविधं"),
        ("श्रृणु", "शृणु"),
        ("पितृ़न्", "पितॄन्"),
        ("कुतो़ऽन्यः", "कुतोऽन्यः"),
    ],
)
def test_legacy_encoding_repairs(broken, fixed):
    assert repair_legacy_encoding(broken)[0] == fixed


def test_correct_text_is_untouched_by_repairs():
    for word in ["निश्चितं", "भक्तिं", "शृणु", "श्रद्धया", "प्रकृति", "क्षेत्रज्ञ"]:
        assert repair_legacy_encoding(word) == (word, [])


def test_lenient_mode_drops_variant_notes_and_hyphens():
    raw = "नभश्च पृथिवीं चैव तुमुलो व्यनुनादयन् (or लोव्यनु) ||१-१९||"
    with pytest.raises(DevanagariError):
        parse_verse(raw)
    assert parse_verse(raw, lenient=True).lines == ["नभश्च पृथिवीं चैव तुमुलो व्यनुनादयन् ॥"]
    joined = parse_verse("तथा शरीराणि विहाय जीर्णा- न्यन्यानि संयाति नवानि देही ||", lenient=True)
    assert "जीर्णान्यन्यानि" in joined.text


def test_rejects_foreign_characters():
    with pytest.raises(DevanagariError):
        parse_verse("धर्मक्षेत्रे kuru ।।1.1।।")


def test_keys():
    assert strict_key("मा फलेषु कदाचन ।") == strict_key("मा  फलेषु\nकदाचन॥")
    assert strict_key("तथाऽपरे") != strict_key("तथापरे")
    assert orthographic_key("तथाऽपरे") == orthographic_key("तथापरे")
    assert orthographic_key("साङ्ख्ये") == orthographic_key("सांख्ये")
