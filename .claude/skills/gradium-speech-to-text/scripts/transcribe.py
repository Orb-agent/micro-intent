#!/usr/bin/env python3
"""Batch transcription with Gradium STT. Tested against api.gradium.ai.

Requires: pip install requests. Input must be WAV, raw PCM, or Ogg/Opus
(convert other formats first: ffmpeg -i in.mp4 -ar 24000 -ac 1 out.wav).

Usage:
  export GRADIUM_API_KEY=...
  python transcribe.py recording.wav --language en
  python transcribe.py call.wav --keywords Gradium Mbappé --boost 3
  python transcribe.py recording.wav --srt captions.srt
"""
import argparse
import json
import os
import sys

import requests

CT = {".wav": "audio/wav", ".pcm": "audio/pcm", ".ogg": "audio/ogg", ".opus": "audio/opus"}


def expand(term: str) -> list[str]:
    """Case variants of a keyword; split multi-word terms into tokens."""
    out = []
    for tok in term.split():
        for v in (tok, tok.lower(), tok.capitalize()):
            if v not in out:
                out.append(v)
    return out


def srt_time(s: float) -> str:
    h, rem = divmod(s, 3600)
    m, sec = divmod(rem, 60)
    return f"{int(h):02}:{int(m):02}:{int(sec):02},{int((sec % 1) * 1000):03}"


def main() -> int:
    p = argparse.ArgumentParser(description="Gradium batch speech-to-text")
    p.add_argument("audio")
    p.add_argument("--language", default=None, help="en|fr|de|es|pt")
    p.add_argument("--keywords", nargs="*", default=None,
                   help="terms to boost (case variants added automatically)")
    p.add_argument("--boost", type=int, default=3, help="-6..6, default 3")
    p.add_argument("--delay", type=int, default=16,
                   help="delay_in_frames 4-80 (higher = better quality, more latency). "
                        "Pinned explicitly because the server default is large and "
                        "timestamps shift by delay*0.08s; 0 can return no words")
    p.add_argument("--srt", default=None, help="also write an SRT file here")
    p.add_argument("--json", action="store_true", help="print word timings as JSON")
    args = p.parse_args()

    key = os.environ.get("GRADIUM_API_KEY")
    if not key:
        print("GRADIUM_API_KEY is not set", file=sys.stderr)
        return 1

    ext = os.path.splitext(args.audio)[1].lower()
    if ext not in CT:
        print(f"unsupported extension {ext}; convert to wav/pcm/ogg first "
              f"(ffmpeg -i {args.audio} -ar 24000 -ac 1 out.wav)", file=sys.stderr)
        return 1

    cfg = {"delay_in_frames": args.delay}
    if args.language:
        cfg["language"] = args.language
    if args.keywords:
        words = [v for t in args.keywords for v in expand(t)]
        cfg["keywords"] = {"words": words, "boost": args.boost}

    with open(args.audio, "rb") as f:
        audio = f.read()

    words = []  # (text, start_s, stop_s|None)
    with requests.post(
        "https://api.gradium.ai/api/post/speech/asr",
        params={"json_config": json.dumps(cfg)} if cfg else None,
        data=audio,
        headers={"x-api-key": key, "Content-Type": CT[ext]},
        stream=True,
        allow_redirects=False,
        timeout=300,
    ) as r:
        if r.status_code != 200:
            print(f"STT failed: HTTP {r.status_code}", file=sys.stderr)
            return 1
        for line in r.iter_lines(decode_unicode=True):
            if not line:
                continue
            m = json.loads(line)
            if m["type"] == "text":
                words.append([m["text"].strip(), m.get("start_s"), None])
            elif m["type"] == "end_text" and words:
                words[-1][2] = m.get("stop_s")
            elif m["type"] == "error":
                print("STT provider returned an error", file=sys.stderr)
                return 1

    # start_s/stop_s run on the decoder clock, which leads the audio by
    # roughly delay_in_frames * 0.08s — shift back to audio time.
    shift = args.delay * 0.08
    for w in words:
        if w[1] is not None:
            w[1] = max(0.0, w[1] - shift)
        if w[2] is not None:
            w[2] = max(0.0, w[2] - shift)

    transcript = " ".join(w[0] for w in words)
    print(transcript)

    if args.json:
        print(json.dumps([{"text": t, "start_s": a, "stop_s": b} for t, a, b in words]))
    if args.srt:
        # group words into ~7-word caption lines
        with open(args.srt, "w") as f:
            group, idx = [], 1
            for w in words:
                group.append(w)
                if len(group) >= 7 or w is words[-1]:
                    start = group[0][1] or 0.0
                    stop = group[-1][2] or group[-1][1] or start + 2.0
                    f.write(f"{idx}\n{srt_time(start)} --> {srt_time(stop)}\n"
                            f"{' '.join(g[0] for g in group)}\n\n")
                    group, idx = [], idx + 1
        print(f"wrote {args.srt}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
