# Architecture

Phono is one Swift package with three targets. Its one dependency is [phonon-coreml](https://github.com/fermionresearch/phonon-coreml), Fermion Research's runner for Phonon-2 on Core ML.

| Target | Contents |
|---|---|
| `PhonoCore` | Foundation only, so it builds and tests on any platform: hotkey presets and the lone-modifier state machine, settings, where the model lives, the server request and reply, and text clean-up. |
| `PhonoKit` | Shared by the Mac and iOS apps: `Recorder` (16 kHz mono from the microphone), the `Transcribing` protocol, and `ServerEngine`, the Phonon server client. |
| `phono` | The macOS app and CLI in one binary. With arguments it runs as a CLI; without, as a menu-bar app. |

## Flow

```
HotkeyManager ─► DictationController ─► Recorder (16 kHz mono)
                        │
                        ├─► SpeechModel ─► Phonon-2 (Core ML, Neural Engine)
                        │              └─► or a Phonon server (HTTP)
                        ├─► ServerStream ─► a Phonon server, live (WebSocket)
                        │
                        └─► Paster (⌘V or typing) and HUD
```

- **SpeechModel** loads Phonon-2 at launch on a background queue and keeps it in memory. On the first launch, Core ML compiles the model for the Mac's Neural Engine, which takes a minute or two; later launches load in about a second. Each clip runs on one serial queue.
- **SpeechModel** holds one `Transcribing` engine, chosen by the Engine setting. `Runner` runs Phonon-2 in this process. `ServerEngine` posts each clip as a 16-bit WAV to a Phonon server's `/v1/audio/transcriptions` (OpenAI's audio API) with a bearer key. It counts as ready once the server transcribes half a second of silence, which also checks the key. Switching engines drops the old one, so the local model's memory is freed.
- **ServerStream** streams one dictation to a Phonon server's `/v1/audio/stream` while the shortcut is held: 16-bit PCM out as the Recorder hears it, and the server's partial and final text back for the HUD's preview. On release it sends `end` and pastes the server's `done` transcript. If the stream fails at any point (the server serves one stream at a time, and older servers have none), DictationController sends the whole clip to `/v1/audio/transcriptions` instead. The local engine has no stream, so it shows no preview.
- **HotkeyManager** registers key combinations with Carbon. A lone modifier (⌥, fn) cannot be registered that way, so it watches global key events instead, which needs Accessibility. `ModifierTriggerState` decides what counts as a press: if another key, modifier, or click joins, the press is interrupted and the audio discarded.
- **DictationController** records from the first instant of a lone-modifier press, but shows the HUD and plays the sound only after 250 ms, so quick taps and ⌥← stay invisible.
- **Recorder** converts to 16 kHz mono on the audio thread. It can keep the microphone open without keeping audio (`open`, then `beginCapture` and `endCapture` per clip), which the iPhone keyboard needs. Its tap closure is built outside the main actor, because Swift 6 traps when the audio thread calls a main-actor closure.
- **Paster** has two ways to insert text. Paste saves the clipboard, writes the text, posts ⌘V, and restores the clipboard 600 ms later unless something else changed it. Type posts one key event per character, with the character attached, and does not touch the clipboard. A second text waits until the first is typed.
- **StatusItemController** builds the menu from `MenuItem`s, whose title, checkmark, and visibility are closures. One `refresh()` updates them all.

## iPhone app and keyboard

`iOS/project.yml` makes an Xcode project with XcodeGen. The app links PhonoCore and PhonoKit and always uses a Phonon server.

A keyboard extension cannot use the microphone, so the app records for it:

1. The keyboard's mic button opens `phono://dictate`. The app turns the microphone on and starts a clip.
2. The user goes back to the other app. The microphone stays open in the background (the `audio` background mode), because iOS does not let an app turn it on from there.
3. Each later tap posts a `toggle` Darwin notification. The app starts or stops a clip, transcribes it, and writes the state and the text to the `group.io.github.eriko13.phono` App Group defaults, then posts `changed`. The keyboard reads them and inserts the text.
4. The app closes the microphone 5 minutes after the last clip, or when a call interrupts it.

`KeyboardLink` in `iOS/Shared` is the whole protocol, compiled into both targets. When the keyboard appears, it posts `ping`; if the app does not answer, the next tap opens the app again. The keyboard needs Full Access to use the App Group. It does not touch the network.

## Model

`Scripts/download-model.sh` puts the model in `~/Library/Application Support/Phono/Phonon-2-CoreML`. The script pins one Hugging Face revision and checks SHA-256 sums. The app never uses the network. `Model.files` in PhonoCore lists the files the app needs; keep it in step with the script.

## Settings

All settings are in the `io.github.eriko13.phono` defaults domain. The app and the bare CLI binary both read from it. The CLI names the suite explicitly, because it has no bundle identifier.
