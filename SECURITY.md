# Security

## What Phono can access

| Access | Why |
|---|---|
| Microphone | Records only while the shortcut is active. Audio stays in memory and is never written to disk. |
| Accessibility | Sees a lone ⌥ or fn key, and whether another key or click came while it was held, but never which key. Posts ⌘V to paste. |
| Clipboard | Writes the transcript, then restores what was there. |
| Network | HTTP to `127.0.0.1` only, to the local engine. |
| Files | Writes `~/Library/Logs/Phono/engine.log`. |

The last 10 transcripts stay in memory for the Recent menu and are gone when Phono quits.

`Scripts/setup-engine.sh` is the only part that uses the internet. It installs Python packages from PyPI and downloads Phonon-2 from Hugging Face.

## Reporting a vulnerability

Use GitHub's private vulnerability reporting on this repository: **Security › Report a vulnerability**. Do not open a public issue.
