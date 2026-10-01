# TTS provider matrix (re-verified for Phase 5, October 2026)

This updates the Phase 1 matrix from current sources. **Verified** means a
current source says so. **Verify** means I could not open the primary page
from this environment (Hugging Face and arXiv are blocked here), so check
it before relying on it.

| Provider | English | Telugu | Sanskrit | Runs on phone | Needs server/GPU | Licence | Status in the app |
|---|---|---|---|---|---|---|---|
| **Android system TTS** (`flutter_tts`) | ✅ en-IN | ✅ te-IN when the voice pack is installed | ❌ (Hindi reads Devanagari, approximate) | ✅ | ❌ | OS | **Implemented** (`DeviceTtsProvider`), first in the chain |
| **AI4Bharat Indic Parler-TTS** | ✅ | ✅ speakers Prakash, Lalitha (verified) | ✅ speakers Aryan, Vasudha (verified) | ❌ (~0.9B params) | ✅ GPU recommended | Apache-2.0 (verified) | **Implemented** for batch recitation (`backend/app/providers/tts/indic_parler.py`) |
| **Piper** (OHF-Voice/piper1-gpl) | ✅ | ✅ te_IN voice exists (verified) | ❌ | ✅ via sherpa-onnx | optional | engine GPL-3.0; voices licensed separately per voice (verify the Telugu model card) | Planned as an on-device neural voice (Phase 9 downloads) |
| **Kokoro-82M** | ✅ | ❌ | ❌ | ✅ via sherpa-onnx | optional | Apache-2.0 | Planned (English, Phase 9) |
| **sherpa-onnx** (runtime) | — | — | — | ✅ Flutter package `sherpa_onnx` 1.13.8 on pub.dev (verified) | ❌ | Apache-2.0 | The runtime for on-device Piper/Kokoro |
| **Vagdhenu** (metre-aware shloka chanting, arXiv 2608.26146) | — | — | ✅ chanting by metre (from the abstract) | verify | verify | verify | Promising for recitation; evaluate once its code, weights and licence can be checked |
| Meta MMS-TTS | ✅ | ✅ | verify | ✅ | ❌ | CC-BY-NC-4.0 (non-commercial) | Not used (non-commercial) |
| Coqui XTTS-v2 | ✅ | ❌ | ❌ | ❌ | ✅ | non-commercial | Not used |

## Order the app uses (cost hierarchy)

1. Already cached audio (content-addressed, so nothing is ever synthesized twice).
2. Device TTS: free, offline, no download.
3. On-device neural voices: Piper/Kokoro via sherpa-onnx (Phase 9, optional downloads).
4. Pre-generated server audio: Indic Parler recitation packs (Phase 9 downloads).
5. Paid APIs: none configured.

## Sanskrit specifically

- Device TTS has no Sanskrit voice, so a Hindi voice reads the Devanagari.
  The player says so: "pronunciation is approximate".
- Indic Parler-TTS supports Sanskrit natively. `workers/generate_recitation.py`
  pre-generates normal and slow recitation for all 701 verses. Every file is
  `unreviewed` in `review.csv` until a Sanskrit-literate listener approves it.
- Slow recitation is a separate synthesis (requested in the voice
  description), not a time-stretch, and has its own cache key.
- Running the batch: a free Kaggle or Colab GPU is enough. 701 verses × 2
  styles ≈ 1,400 clips of about 10–20 s.

Sources:
- [ai4bharat/indic-parler-tts](https://huggingface.co/ai4bharat/indic-parler-tts-pretrained)
- [Piper voices (OHF-Voice/piper1-gpl)](https://github.com/OHF-Voice/piper1-gpl/blob/main/docs/VOICES.md)
- [piper-tts on PyPI](https://pypi.org/project/piper-tts/)
- [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx)
- [sherpa_onnx Flutter package](https://pub.dev/packages/sherpa_onnx/changelog)
- [Vagdhenu (arXiv 2608.26146)](https://arxiv.org/pdf/2608.26146)
