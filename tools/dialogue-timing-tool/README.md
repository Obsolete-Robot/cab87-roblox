# Dialogue Timing Tool

Browser tool for turning dialogue audio into word-level timing data for kinetic text, captions, and edit markers.

## Run

Set an OpenAI API key in your shell, then start the local server:

```sh
cd tools/dialogue-timing-tool
OPENAI_API_KEY=sk-... npm run dev
```

Open `http://127.0.0.1:8011`.

Windows PowerShell:

```powershell
cd tools/dialogue-timing-tool
$env:OPENAI_API_KEY = "sk-..."
npm run dev
```

The API key stays on the local Node server. The browser uploads the selected clip to `POST /api/transcribe`, and the server forwards it to OpenAI with `model=whisper-1`, `response_format=verbose_json`, and word plus segment timestamp granularities.

## Workflow

1. Choose an audio or video clip.
2. Add an optional language code or prompt context for names and unusual terms.
3. Click **Transcribe**.
4. Review the word timing against the waveform and audio preview.
5. Use **Play** to watch the current word highlight against the clip.
6. Click **Hide Sidebar** when you want the transcript workspace to fill the page.
7. Nudge or edit any word start/end values that need tighter kinetic text timing, use **Prev +50/+100** and **Next +50/+100** to borrow timing from adjacent words, or click **Trash** to remove unwanted words.
8. If a row contains combined words, add a space in the word text and click **Split**. The tool divides the original timing proportionally between the two new word rows.
9. Export kinetic JSON, CSV, VTT, or SRT.

## Notes

- OpenAI audio uploads are limited to 25 MB by default. This tool enforces the same default with `MAX_AUDIO_BYTES`.
- Word timestamps are model-estimated. For frame-critical animation, review the waveform and use the timing editor before final export.
- `Import JSON` accepts OpenAI `verbose_json` responses and simple `{ "words": [{ "word": "...", "start": 0, "end": 1 }] }` timing files from other engines.
- To change the port, run `PORT=8020 npm run dev`.
