from fastapi import FastAPI, HTTPException, Form, UploadFile, File, Body
from fastapi.responses import StreamingResponse, JSONResponse
from fastapi.middleware.cors import CORSMiddleware
from PIL import Image
import io
import google.generativeai as genai
import asyncio
from io import BytesIO
import requests
from transformers import AutoTokenizer
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

GEMINI_API_KEY = "AIzaSyDSj2COlfNWGsHUGmrxNsJ64Ui32PNAka8"
genai.configure(api_key=GEMINI_API_KEY)

INTERIOR_ASSISTANT_PROMPT = (
    "You are an expert interior design assistant. "
    "Answer user questions about room decoration, furniture, color schemes, and home improvement in a helpful, concise, and friendly way."
)

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
        print(f"[DEBUG] Received chat message: {message}")
        if is_image_request(message):
            print("[DEBUG] Detected image request, calling Gemini API...")
            user_prompt = f"{INTERIOR_ASSISTANT_PROMPT}\nUser: {message}\nAssistant:"
            client = genai.GenerativeModel("gemini-2.5-flash")
            loop = asyncio.get_event_loop()
            response = await loop.run_in_executor(None, client.generate_content, user_prompt)
            print(f"[DEBUG] Gemini response: {response}")
            if hasattr(response, "image"):
                img_bytes = response.image
                print("[DEBUG] Gemini returned image bytes.")
                return StreamingResponse(BytesIO(img_bytes), media_type="image/png")
            if hasattr(response, "images") and response.images:
                img_bytes = response.images[0]
                print("[DEBUG] Gemini returned images list.")
                return StreamingResponse(BytesIO(img_bytes), media_type="image/png")
            print("[DEBUG] Gemini did not return image, returning text.")
            return {"reply": response.text.strip()}
        else:
            print("[DEBUG] Detected text chat, calling Gemini API...")
            user_prompt = f"{INTERIOR_ASSISTANT_PROMPT}\nUser: {message}\nAssistant:"
            client = genai.GenerativeModel("gemini-2.5-flash")
            loop = asyncio.get_event_loop()
            response = await loop.run_in_executor(None, client.generate_content, user_prompt)
            print(f"[DEBUG] Gemini response: {response}")
            return {"reply": response.text.strip()}
    except Exception as e:
        print(f"[ERROR] Chat/image error: {e}")
        return JSONResponse(status_code=500, content={"detail": f"Chat/image error: {e}"})

@app.post("/generate_gemini_image")
async def generate_gemini_image(prompt: str = Form(...), file: UploadFile = File(...)):
    try:
        image_data = await file.read()
        image = Image.open(io.BytesIO(image_data))
        model = genai.GenerativeModel("gemini-2.5-flash-image")
        response = model.generate_content([prompt, image])
        for part in response.parts:
            if part.text is not None:
                return JSONResponse(status_code=200, content={"text": part.text})
            elif part.inline_data is not None:
                gen_image = part.as_image()
                buf = io.BytesIO()
                gen_image.save(buf, format="PNG")
                buf.seek(0)
                return StreamingResponse(buf, media_type="image/png")
        return JSONResponse(status_code=500, content={"detail": "No valid response from Gemini API."})
    except Exception as e:
        import traceback
        print("Gemini image generation error:", e)
        traceback.print_exc()
        return JSONResponse(status_code=500, content={"detail": f"Gemini image generation error: {e}"})

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

# Store chat objects in memory for demo purposes
chats = {}

@app.post("/gemini_chat")
async def gemini_chat(
    chat_id: str = Form(...),
    message: str = Form(...),
    file: UploadFile = File(None)
):
    try:
        # Create or get chat
        if chat_id not in chats:
            chats[chat_id] = genai.Client().chats.create(
                model="gemini-3-pro-image-preview",
                config={
                    "response_modalities": ["TEXT", "IMAGE"],
                    "tools": [{"google_search": {}}]
                }
            )
        chat = chats[chat_id]
        contents = [message]
        if file:
            image_data = await file.read()
            image = Image.open(io.BytesIO(image_data))
            contents.append(image)
        response = chat.send_message(contents)
        results = []
        for part in response.parts:
            if part.text is not None:
                results.append({"type": "text", "content": part.text})
            elif part.as_image():
                gen_image = part.as_image()
                buf = io.BytesIO()
                gen_image.save(buf, format="PNG")
                buf.seek(0)
                results.append({"type": "image", "content": buf.getvalue()})
        if not results:
            return JSONResponse(status_code=500, content={"detail": "No valid response from Gemini API."})
        # For images, return as StreamingResponse; for text, return as JSON
        for r in results:
            if r["type"] == "image":
                return StreamingResponse(io.BytesIO(r["content"]), media_type="image/png")
        return JSONResponse(status_code=200, content={"results": results})
    except Exception as e:
        return JSONResponse(status_code=500, content={"detail": f"Gemini chat error: {e}"})