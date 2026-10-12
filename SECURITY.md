# Security

## What Phono can access

| Access | Why |
|---|---|
| Microphone | Records only while the shortcut is active. Audio stays in memory and is never written to disk. |
| Accessibility | Sees a lone ⌥ or fn key, and whether another key or click came while it was held, but never which key. Posts ⌘V to paste. |
| Clipboard | Writes the transcript, then restores what was there. |
| Network | None. |
| Files | Reads the model in `~/Library/Application Support/Phono`. Core ML keeps its compiled copy in `~/Library/Caches/phonon-coreml`. |

The last 10 transcripts stay in memory for the Recent menu and are gone when Phono quits.

`Scripts/download-model.sh` is the only part that uses the internet. It downloads Phonon-2 from one pinned Hugging Face revision and checks every file against a SHA-256 sum. Building Phono also fetches the [phonon-coreml](https://github.com/fermionresearch/phonon-coreml) Swift package at a pinned version.

## Reporting a vulnerability

Use GitHub's private vulnerability reporting on this repository: **Security › Report a vulnerability**. Do not open a public issue.
