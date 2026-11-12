"""Generates the captain radio chatter lines with ElevenLabs.

Reads data/radio/radio_lines.json and writes
assets/audio/voice/radio/<personality>_<slot>/<event>_<n>.mp3 for every line
and both voice slots. Existing files are skipped unless --force; --only=a,b
limits to personalities, --event=x to one event. Key: ~/.config/elevenlabs/api_key
(never printed). Run Godot --headless --path . --import afterwards.

    python3 -I tools/gen_radio_lines.py [--force] [--only=bold] [--event=kill]
"""
import json
import os
import sys
import time
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TABLE = os.path.join(ROOT, "data", "radio", "radio_lines.json")
OUT = os.path.join(ROOT, "assets", "audio", "voice", "radio")
URL = "https://api.elevenlabs.io/v1/text-to-speech/%s?output_format=mp3_44100_128"
SEED = 7


def main():
    force = "--force" in sys.argv
    only = None
    event = None
    for a in sys.argv[1:]:
        if a.startswith("--only="):
            only = set(a.split("=", 1)[1].split(","))
        if a.startswith("--event="):
            event = a.split("=", 1)[1]
    key = open(os.path.expanduser("~/.config/elevenlabs/api_key")).read().strip()
    d = json.load(open(TABLE))
    made = skipped = failed = 0
    for pers, events in d["lines"].items():
        if only and pers not in only:
            continue
        for slot, voice in enumerate(d["voices"][pers]):
            folder = os.path.join(OUT, "%s_%d" % (pers, slot))
            os.makedirs(folder, exist_ok=True)
            for ev, texts in events.items():
                if event and ev != event:
                    continue
                for n, text in enumerate(texts):
                    path = os.path.join(folder, "%s_%d.mp3" % (ev, n))
                    if os.path.exists(path) and not force:
                        skipped += 1
                        continue
                    body = json.dumps({"text": text, "model_id": d["model_id"], "seed": SEED,
                                       "voice_settings": d["voice_settings"]}).encode()
                    req = urllib.request.Request(URL % voice, data=body, method="POST",
                                                 headers={"xi-api-key": key, "Content-Type": "application/json"})
                    for attempt in range(3):
                        try:
                            with urllib.request.urlopen(req, timeout=60) as r:
                                open(path, "wb").write(r.read())
                            made += 1
                            print("made %s_%d/%s_%d" % (pers, slot, ev, n), flush=True)
                            break
                        except Exception as e:
                            print("retry %s_%d/%s_%d: %s" % (pers, slot, ev, n, getattr(e, "code", e)), flush=True)
                            time.sleep(3 + attempt * 5)
                    else:
                        failed += 1
                    time.sleep(0.3)
    print("done: %d made, %d skipped, %d failed" % (made, skipped, failed), flush=True)


if __name__ == "__main__":
    main()
