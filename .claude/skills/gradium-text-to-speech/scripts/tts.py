#!/usr/bin/env python3
"""One-shot Gradium TTS: text in, audio file out.

Tested against api.gradium.ai. Requires: pip install requests

Usage:
  export GRADIUM_API_KEY=...
  python tts.py "Hello, world!" --out hello.wav
  python tts.py "Read faster" --speed fast --format opus --out fast.ogg
  python tts.py "Deterministic take" --temp 0 --voice YTpq7expH9539ERJ
"""
import argparse
import os
import sys

import requests

SPEED = {"fast": -2.0, "normal": 0.0, "slow": 2.0}
EXT = {"wav": ".wav", "opus": ".ogg", "pcm": ".pcm"}


def main() -> int:
    p = argparse.ArgumentParser(description="Gradium text-to-speech")
    p.add_argument("text")
    p.add_argument("--voice", default="YTpq7expH9539ERJ", help="Gradium voice_id")
    p.add_argument("--out", default=None, help="output path (default: speech.<ext>)")
    p.add_argument("--format", default="wav",
                   help="wav|opus|pcm|pcm_16000|ulaw_8000|alaw_8000|...")
    p.add_argument("--speed", choices=SPEED, default=None,
                   help="preset pace (fast=-2.0, slow=+2.0 padding_bonus)")
    p.add_argument("--padding", type=float, default=None, metavar="B",
                   help="numeric padding_bonus -4.0..4.0 for finer pace control "
                        "(negative=faster; ±1.0 = 'slightly'); overrides --speed")
    p.add_argument("--temp", type=float, default=None, help="0.0-1.4, 0=deterministic")
    p.add_argument("--rewrite", default=None, metavar="LANG",
                   help="enable text normalization rules, e.g. en")
    args = p.parse_args()

    key = os.environ.get("GRADIUM_API_KEY")
    if not key:
        print("GRADIUM_API_KEY is not set", file=sys.stderr)
        return 1

    body = {"text": args.text, "voice_id": args.voice,
            "output_format": args.format, "only_audio": True}
    cfg = {}
    if args.speed:
        cfg["padding_bonus"] = SPEED[args.speed]
    if args.padding is not None:
        cfg["padding_bonus"] = args.padding
    if args.temp is not None:
        cfg["temp"] = args.temp
    if args.rewrite:
        cfg["rewrite_rules"] = args.rewrite
    if cfg:
        body["json_config"] = cfg

    r = requests.post("https://api.gradium.ai/api/post/speech/tts",
                      json=body, headers={"x-api-key": key}, timeout=120,
                      allow_redirects=False)
    if r.status_code != 200:
        print(f"TTS failed: HTTP {r.status_code}", file=sys.stderr)
        return 1

    out = args.out or "speech" + EXT.get(args.format, ".bin")
    with open(out, "wb") as f:
        f.write(r.content)
    print(f"wrote {out} ({len(r.content)} bytes, {args.format})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
