"""Single OpenAI-compatible entrypoint"""

import os
from io import BytesIO

import httpx
import soundfile as sf
import torch
import uvicorn
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import Response, StreamingResponse
from pydantic import BaseModel
from qwen_tts import Qwen3TTSModel

TTS_MODEL = os.environ.get("TTS_MODEL", "Qwen/Qwen3-TTS-12Hz-0.6B-CustomVoice")
PORT = int(os.environ.get("GATEWAY_PORT", "8000"))
LLAMA_URL = "http://127.0.0.1:8081"
_VOICES = {"default": "Ryan"}
_LANGUAGE = "English"

app = FastAPI()
llama = httpx.AsyncClient(base_url=LLAMA_URL, timeout=None)
tts: Qwen3TTSModel | None = None


class SpeechRequest(BaseModel):
    model: str
    input: str
    voice: str
    instructions: str | None = None
    response_format: str = "mp3"


@app.on_event("startup")
def load_tts() -> None:
    global tts
    device = "cuda" if torch.cuda.is_available() else "cpu"
    tts = Qwen3TTSModel.from_pretrained(
        TTS_MODEL,
        device_map=device,
        dtype=torch.bfloat16 if device == "cuda" else torch.float32,
    )


@app.get("/health")
async def health() -> dict[str, bool]:
    response = await llama.get("/health")
    if response.status_code != 200 or tts is None:
        raise HTTPException(status_code=503)

    return {"ready": True}


@app.post("/v1/chat/completions")
async def chat_completions(request: Request) -> StreamingResponse:
    upstream = await llama.send(
        llama.build_request(
            "POST",
            "/v1/chat/completions",
            content=await request.body(),
            headers={"content-type": "application/json"},
        ),
        stream=True,
    )

    return StreamingResponse(
        upstream.aiter_raw(),
        status_code=upstream.status_code,
        media_type=upstream.headers.get("content-type"),
        background=upstream.aclose,
    )


@app.post("/v1/audio/speech")
def speech(request: SpeechRequest) -> Response:
    speaker = _VOICES.get(request.voice)
    if speaker is None:
        raise HTTPException(status_code=422, detail=f"Unknown voice: {request.voice}")

    if request.response_format != "mp3":
        raise HTTPException(
            status_code=422, detail=f"Unsupported response_format: {request.response_format}"
        )

    wavs, sample_rate = tts.generate_custom_voice(
        text=request.input,
        language=_LANGUAGE,
        speaker=speaker,
        instruct=request.instructions,
    )

    buffer = BytesIO()
    sf.write(buffer, wavs[0], sample_rate, format="MP3")

    return Response(content=buffer.getvalue(), media_type="audio/mpeg")


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=PORT)
