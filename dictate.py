"""
================================================================================
  VoiceDictate - System-Wide Whisper Dictation Tool
  Hotkey: F9 (toggle listen ON/OFF)
  Model:  base
  Output: Auto-paste transcribed text at cursor position
================================================================================
  Dependencies:
    py -m pip install faster-whisper sounddevice numpy keyboard pyautogui pyperclip pystray Pillow
================================================================================
"""

import threading
import time
import sys
import os
import tempfile
import wave

import sounddevice as sd
import numpy as np
import keyboard
import pyautogui
import pyperclip
from faster_whisper import WhisperModel
import pystray
from PIL import Image, ImageDraw

# ══════════════════════════════════════════════════════════════════════════════
#  CONFIG
# ══════════════════════════════════════════════════════════════════════════════
HOTKEY          = "f9"
MODEL_SIZE      = "base"
SAMPLE_RATE     = 16000
CHANNELS        = 1
CHUNK           = 1024
SILENCE_TIMEOUT = 2.0       # seconds of silence before auto-stop
SILENCE_THRESH  = 0.01      # RMS volume threshold (0.0-1.0)
COMPUTE_TYPE    = "int8"

# ══════════════════════════════════════════════════════════════════════════════
#  GLOBALS
# ══════════════════════════════════════════════════════════════════════════════
is_listening = False
model        = None
tray_icon    = None

# ══════════════════════════════════════════════════════════════════════════════
#  TRAY ICON
# ══════════════════════════════════════════════════════════════════════════════

def make_icon(listening):
    size = 64
    img  = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    color = (50, 200, 80) if listening else (120, 120, 120)
    draw.ellipse([4, 4, size-4, size-4], fill=color)
    cx, cy, r = size//2, size//2, size//6
    draw.ellipse([cx-r, cy-r, cx+r, cy+r], fill=(255, 255, 255))
    return img

def update_tray():
    global tray_icon
    if tray_icon is None:
        return
    tray_icon.icon  = make_icon(is_listening)
    tray_icon.title = ("VoiceDictate — Listening (F9 to stop)"
                       if is_listening else
                       "VoiceDictate — Idle (F9 to start)")

def quit_app(icon, item):
    icon.stop()
    keyboard.unhook_all()
    os._exit(0)

def run_tray():
    global tray_icon
    menu = pystray.Menu(
        pystray.MenuItem("VoiceDictate", None, enabled=False),
        pystray.MenuItem("F9 to toggle listening", None, enabled=False),
        pystray.Menu.SEPARATOR,
        pystray.MenuItem("Quit", quit_app),
    )
    tray_icon = pystray.Icon("VoiceDictate", make_icon(False),
                             "VoiceDictate — Idle (F9 to start)", menu)
    tray_icon.run()

# ══════════════════════════════════════════════════════════════════════════════
#  AUDIO RECORDING  (sounddevice — works on Python 3.14)
# ══════════════════════════════════════════════════════════════════════════════

def record_audio():
    global is_listening
    collected     = []
    silent_chunks = [0]
    max_silent    = int(SILENCE_TIMEOUT * SAMPLE_RATE / CHUNK)

    print("[VoiceDictate] Recording...")

    def callback(indata, frames, time_info, status):
        chunk = indata.copy()
        collected.append(chunk)
        rms = float(np.sqrt(np.mean(chunk ** 2)))
        if rms < SILENCE_THRESH:
            silent_chunks[0] += 1
            if silent_chunks[0] >= max_silent:
                print("[VoiceDictate] Silence detected — stopping.")
                raise sd.CallbackStop()
        else:
            silent_chunks[0] = 0

    try:
        with sd.InputStream(samplerate=SAMPLE_RATE, channels=CHANNELS,
                            dtype="float32", blocksize=CHUNK, callback=callback):
            while is_listening:
                time.sleep(0.05)
    except sd.CallbackStop:
        is_listening = False

    if not collected:
        return np.array([], dtype="float32")
    return np.concatenate(collected, axis=0).flatten()

# ══════════════════════════════════════════════════════════════════════════════
#  TRANSCRIPTION + PASTE
# ══════════════════════════════════════════════════════════════════════════════

def transcribe_and_paste(audio):
    if audio is None or len(audio) == 0:
        print("[VoiceDictate] No audio captured.")
        return

    # Convert float32 -> int16 WAV
    audio_int16 = (audio * 32767).astype(np.int16)
    tmp = tempfile.NamedTemporaryFile(suffix=".wav", delete=False)
    tmp_path = tmp.name
    tmp.close()

    with wave.open(tmp_path, "wb") as wf:
        wf.setnchannels(CHANNELS)
        wf.setsampwidth(2)
        wf.setframerate(SAMPLE_RATE)
        wf.writeframes(audio_int16.tobytes())

    print("[VoiceDictate] Transcribing...")
    segments, _ = model.transcribe(tmp_path, beam_size=5, language="en", vad_filter=True)
    text = " ".join(seg.text.strip() for seg in segments).strip()

    try:
        os.unlink(tmp_path)
    except Exception:
        pass

    if not text:
        print("[VoiceDictate] No speech detected.")
        return

    print(f"[VoiceDictate] Transcribed: {text}")

    original = pyperclip.paste()
    pyperclip.copy(text)
    time.sleep(0.1)
    pyautogui.hotkey("ctrl", "v")
    time.sleep(0.15)
    pyperclip.copy(original)
    update_tray()

# ══════════════════════════════════════════════════════════════════════════════
#  HOTKEY HANDLER
# ══════════════════════════════════════════════════════════════════════════════

def on_f9():
    global is_listening
    if is_listening:
        print("[VoiceDictate] Stopping.")
        is_listening = False
        update_tray()
    else:
        is_listening = True
        update_tray()

        def session():
            global is_listening
            audio = record_audio()
            is_listening = False
            update_tray()
            transcribe_and_paste(audio)

        threading.Thread(target=session, daemon=True).start()

# ══════════════════════════════════════════════════════════════════════════════
#  STARTUP
# ══════════════════════════════════════════════════════════════════════════════

def load_model():
    global model
    print(f"[VoiceDictate] Loading Whisper '{MODEL_SIZE}' model...")
    print("  (First run downloads ~150MB — please wait)")
    model = WhisperModel(MODEL_SIZE, device="cpu", compute_type=COMPUTE_TYPE)
    print("[VoiceDictate] Model ready. Press F9 anywhere to start dictating.")

def main():
    load_model()
    keyboard.add_hotkey(HOTKEY, on_f9, suppress=False)
    print(f"[VoiceDictate] Hotkey: {HOTKEY.upper()} active. Check system tray.")
    threading.Thread(target=run_tray, daemon=True).start()
    try:
        keyboard.wait()
    except KeyboardInterrupt:
        sys.exit(0)

if __name__ == "__main__":
    main()
