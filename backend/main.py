from fastapi import FastAPI, HTTPException, Form, UploadFile, File
from fastapi.responses import StreamingResponse, JSONResponse
from fastapi.middleware.cors import CORSMiddleware
import google.generativeai as genai
import asyncio
from io import BytesIO
import requests
from diffusers import StableDiffusionPipeline
import torch
import re

app = FastAPI()
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Allow all for emulator/dev
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

GEMINI_API_KEY = "AIzaSyCfWiKmGabI7xh6AdwSvVaQ2EEtu-o_NKo"
genai.configure(api_key=GEMINI_API_KEY)

INTERIOR_ASSISTANT_PROMPT = (
    "You are an expert interior design assistant. "
    "Answer user questions about room decoration, furniture, color schemes, and home improvement in a helpful, concise, and friendly way."
)

# Load Stable Diffusion pipeline at startup (text-to-image)
pipe = StableDiffusionPipeline.from_pretrained(
    "stabilityai/stable-diffusion-2-1-base",
    torch_dtype=torch.float32
)
pipe.to("cpu")

def is_image_request(message: str) -> bool:
    # Simple heuristic: look for 'show', 'generate', 'picture', 'image', 'draw', 'visualize', etc.
    keywords = [
        r"show (me )?(an?|the)? ?(image|picture|photo|render|drawing)",
        r"generate (an?|the)? ?(image|picture|photo|render|drawing)",
        r"draw (an?|the)? ?(image|picture|photo|render|drawing)",
        r"visualize",
        r"create (an?|the)? ?(image|picture|photo|render|drawing)"
    ]
    for kw in keywords:
        if re.search(kw, message, re.IGNORECASE):
            return True
    # Also, if user says 'make a picture of ...' or 'I want a picture of ...'
    if re.search(r"(picture|image|photo|drawing) of", message, re.IGNORECASE):
        return True
    return False

@app.post("/chat")
async def chat(message: str = Form(...)):
    try:
        if is_image_request(message):
            # Use Stable Diffusion for image generation
            result = pipe(message.strip(), num_inference_steps=30).images[0]
            output_buffer = BytesIO()
            result.save(output_buffer, format="PNG")
            output_buffer.seek(0)
            return StreamingResponse(output_buffer, media_type="image/png")
        else:
            # Use Gemini for normal chat
            user_prompt = f"{INTERIOR_ASSISTANT_PROMPT}\nUser: {message}\nAssistant:"
            client = genai.GenerativeModel("gemini-2.5-flash")
            loop = asyncio.get_event_loop()
            response = await loop.run_in_executor(None, client.generate_content, user_prompt)
            return {"reply": response.text.strip()}
    except Exception as e:
        return JSONResponse(status_code=500, content={"detail": f"Chat/image error: {e}"})

@app.post("/decorate")
async def decorate(prompt: str = Form(...)):
    try:
        if not prompt or not prompt.strip():
            raise HTTPException(status_code=400, detail="Prompt must not be empty.")
        # Always use Stable Diffusion for /decorate
        result = pipe(prompt.strip(), num_inference_steps=30).images[0]
        output_buffer = BytesIO()
        result.save(output_buffer, format="PNG")
        output_buffer.seek(0)
        return StreamingResponse(output_buffer, media_type="image/png")
    except HTTPException:
        raise
    except Exception as e:
        return JSONResponse(status_code=500, content={"detail": f"Diffusion image generation error: {e}"})