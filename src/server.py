"""Single OpenAI-compatible entrypoint"""

import os
from collections.abc import AsyncIterator
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

    async def relay() -> AsyncIterator[bytes]:
        """
        Always close upstream, even if the client disconnects mid-stream, so llama-server stops generating.
        This function will not prevent the smart-novel-llm-gateway from generating the response. So even if client timeout/disconnect itself we cleanup the slots

        A slot is one of llama-server's parallel request workers. It's a llama.cpp concept, not something from our code.

        - What it holds: each slot has its own context (KV cache) and generation state, so the server can work on several requests at once.
        - How many: here there are four (ids 0 to 3), all sharing --ctx-size 32768. Each request that comes in takes a free slot and keeps it until its generation finishes or is aborted.
        - What it means for us: when all four are busy, new requests wait. They also compete for the same CPU, so every request slows down.

        That's why the orphans mattered. Beatrice's original call and its two retries each took a slot (0, 1 and 2), and my test took slot 3. Each kept generating after its caller had stopped listening, so nothing was left free for new requests.
        """
        try:
            async for chunk in upstream.aiter_raw():
                yield chunk
        finally:
            await upstream.aclose()

    return StreamingResponse(
        relay(),
        status_code=upstream.status_code,
        media_type=upstream.headers.get("content-type"),
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
