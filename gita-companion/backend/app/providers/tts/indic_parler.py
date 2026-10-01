"""AI4Bharat Indic Parler-TTS adapter (Apache-2.0).

The model lists Sanskrit and Telugu among its supported languages, with
named speakers per language. It is ~0.9B parameters, so use a GPU; it is
meant for batch pre-generation, not on-device use.

Requires (not installed by default): torch, transformers,
parler-tts (git+https://github.com/huggingface/parler-tts), numpy.
Model card: https://huggingface.co/ai4bharat/indic-parler-tts — verify the
licence and speaker names there before a production run.
"""

from __future__ import annotations

from .base import Capabilities, SynthesisResult, Voice, wav_bytes, wav_seconds

MODEL_ID = "ai4bharat/indic-parler-tts"

# Speaker names published on the model card (verify before use).
SPEAKERS = {
    "sa": [("Aryan", "male"), ("Vasudha", "female")],
    "te": [("Prakash", "male"), ("Lalitha", "female")],
    "en": [("Thoma", "male"), ("Mary", "female")],
}

# Parler models are steered by a natural-language description. Slow
# recitation is requested in the description rather than by time-stretching.
DESCRIPTION = (
    "{name} recites in a calm, devotional and clear voice at a {pace} pace, with distinct "
    "pauses between phrases. The recording is very clear with no background noise."
)


def describe(name: str, rate: float) -> str:
    pace = "slow" if rate < 0.85 else ("moderate" if rate <= 1.15 else "slightly fast")
    return DESCRIPTION.format(name=name, pace=pace)


class IndicParlerProvider:
    id = "indic-parler"
    version = "1"

    def __init__(self, device: str | None = None, model_id: str = MODEL_ID):
        self._device = device
        self._model_id = model_id
        self._model = None
        self._tok = None
        self._desc_tok = None

    def capabilities(self) -> Capabilities:
        return Capabilities(
            languages=frozenset(SPEAKERS),
            native_sanskrit=True,
            streaming=False,
            local=False,
            max_chars=600,
            needs_gpu=True,
            license="Apache-2.0",
        )

    def voices(self, language: str | None = None) -> list[Voice]:
        out = []
        for lang, speakers in SPEAKERS.items():
            if language and lang != language:
                continue
            out += [Voice(id=f"{lang}:{n}", language=lang, name=n, gender=g) for n, g in speakers]
        return out

    def _load(self):
        if self._model is not None:
            return
        import torch
        from parler_tts import ParlerTTSForConditionalGeneration
        from transformers import AutoTokenizer

        device = self._device or ("cuda:0" if torch.cuda.is_available() else "cpu")
        self._device = device
        self._model = ParlerTTSForConditionalGeneration.from_pretrained(self._model_id).to(device)
        self._tok = AutoTokenizer.from_pretrained(self._model_id)
        self._desc_tok = AutoTokenizer.from_pretrained(self._model.config.text_encoder._name_or_path)

    def synthesize(self, text: str, voice: Voice, *, rate: float = 1.0) -> SynthesisResult:
        self._load()
        import torch

        description = describe(voice.name, rate)
        desc = self._desc_tok(description, return_tensors="pt").to(self._device)
        prompt = self._tok(text, return_tensors="pt").to(self._device)
        with torch.inference_mode():
            audio = self._model.generate(
                input_ids=desc.input_ids,
                attention_mask=desc.attention_mask,
                prompt_input_ids=prompt.input_ids,
                prompt_attention_mask=prompt.attention_mask,
            )
        samples = audio.cpu().numpy().squeeze()
        sr = int(self._model.config.sampling_rate)
        data = wav_bytes(samples, sr)
        return SynthesisResult(
            wav=data,
            sample_rate=sr,
            seconds=wav_seconds(data),
            meta={"model": self._model_id, "description": description},
        )
