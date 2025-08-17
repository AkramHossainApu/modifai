from fastapi import FastAPI, HTTPException, Form, UploadFile, File, Body
from fastapi.responses import StreamingResponse, JSONResponse
from fastapi.middleware.cors import CORSMiddleware
import google.generativeai as genai
import asyncio
from io import BytesIO
import requests
from diffusers import StableDiffusionPipeline
import torch
import re
from typing import List
from pydantic import BaseModel
from google_auth_oauthlib.flow import InstalledAppFlow
from google.oauth2.credentials import Credentials
from googleapiclient.discovery import build
from googleapiclient.http import MediaIoBaseUpload
from google.auth.transport.requests import Request
import os
import io
import json

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

# Load Stable Diffusion img2img pipeline at startup (image-to-image)
from diffusers import StableDiffusionImg2ImgPipeline
img2img_pipe = StableDiffusionImg2ImgPipeline.from_pretrained(
    "stabilityai/stable-diffusion-2-1-base",
    torch_dtype=torch.float32
)
img2img_pipe.to("cpu")

# In-memory chat storage (for demo; use a database in production)
chat_store = {}

class ChatMessage(BaseModel):
    sender: str
    receiver: str
    text: str
    timestamp: float

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
async def decorate(
    prompt: str = Form(...),
    file: UploadFile = File(None)
):
    try:
        if not prompt or not prompt.strip():
            raise HTTPException(status_code=400, detail="Prompt must not be empty.")
        if file is not None:
            # Image-to-image: modify the uploaded image according to the prompt
            from PIL import Image
            init_image = Image.open(file.file).convert("RGB")
            # Resize to 512x512 for Stable Diffusion (or match model requirements)
            init_image = init_image.resize((512, 512))
            # Use preloaded img2img pipeline
            result = img2img_pipe(prompt=prompt.strip(), image=init_image, strength=0.75, num_inference_steps=30).images[0]
        else:
            # Text-to-image: generate from prompt only
            result = pipe(prompt.strip(), num_inference_steps=30).images[0]
        output_buffer = BytesIO()
        result.save(output_buffer, format="PNG")
        output_buffer.seek(0)
        return StreamingResponse(output_buffer, media_type="image/png")
    except HTTPException:
        raise
    except Exception as e:
        return JSONResponse(status_code=500, content={"detail": f"Diffusion image generation error: {e}"})

@app.post("/chat/send")
def send_message(msg: ChatMessage):
    key = tuple(sorted([msg.sender, msg.receiver]))
    chat_store.setdefault(key, []).append(msg.dict())
    return {"status": "ok"}

@app.get("/chat/history")
def get_history(user1: str, user2: str) -> List[ChatMessage]:
    key = tuple(sorted([user1, user2]))
    messages = chat_store.get(key, [])
    return messages

DRIVE_SCOPES = ['https://www.googleapis.com/auth/drive.file', 'https://www.googleapis.com/auth/drive']
CLIENT_SECRETS_FILE = os.path.join(os.path.dirname(__file__), 'client_secret_812476518688-1ectn86112qc4fbpms1rgllnddacr9v3.apps.googleusercontent.com.json')
TOKEN_FILE = os.path.join(os.path.dirname(__file__), 'token.json')

def get_drive_credentials():
    creds = None
    if os.path.exists(TOKEN_FILE):
        try:
            creds_data = json.load(open(TOKEN_FILE, 'r'))
            creds = Credentials.from_authorized_user_info(creds_data, scopes=DRIVE_SCOPES)
        except Exception:
            creds = None
    if not creds or not creds.valid:
        if creds and creds.expired and creds.refresh_token:
            creds.refresh(Request())
        else:
            if not os.path.exists(CLIENT_SECRETS_FILE):
                raise FileNotFoundError(f"Client secrets not found at {CLIENT_SECRETS_FILE}. Place your JSON there.")
            flow = InstalledAppFlow.from_client_secrets_file(CLIENT_SECRETS_FILE, DRIVE_SCOPES)
            creds = flow.run_local_server(port=0)
            with open(TOKEN_FILE, 'w') as f:
                f.write(creds.to_json())
    return creds

def upload_bytes_to_drive(file_bytes: bytes, filename: str, mime_type: str = 'image/png') -> str:
    creds = get_drive_credentials()
    drive_service = build('drive', 'v3', credentials=creds)
    media = MediaIoBaseUpload(io.BytesIO(file_bytes), mimetype=mime_type, resumable=True)
    file_metadata = {'name': filename}
    file = drive_service.files().create(body=file_metadata, media_body=media, fields='id').execute()
    file_id = file.get('id')
    drive_service.permissions().create(fileId=file_id, body={'type': 'anyone', 'role': 'reader'}).execute()
    share_url = f'https://drive.google.com/uc?export=view&id={file_id}'
    return share_url

@app.post('/upload_drive')
async def upload_drive(file: UploadFile = File(...)):
    try:
        data = await file.read()
        mime = file.content_type or 'application/octet-stream'
        url = upload_bytes_to_drive(data, file.filename, mime)
        return JSONResponse(status_code=200, content={'url': url})
    except Exception as e:
        print(f"Drive upload error: {e}")  # Print error for debugging
        return JSONResponse(status_code=500, content={'detail': f'Drive upload error: {e}'})