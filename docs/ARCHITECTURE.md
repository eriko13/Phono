# Architecture

Phono is one Swift package with three targets. Its one dependency is [phonon-coreml](https://github.com/fermionresearch/phonon-coreml), Fermion Research's runner for Phonon-2 on Core ML.

| Target | Contents |
|---|---|
| `PhonoCore` | Foundation only, so it builds and tests on any platform: hotkey presets and the lone-modifier state machine, settings, where the model lives, the server request and reply, text clean-up, and the iPhone keyboard's typing rules and next-word predictions. |
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
- **Recorder** converts to 16 kHz mono on the audio thread. It can open the microphone without keeping audio (`open`, then `beginCapture` and `endCapture` per clip), which the iPhone's Talk button needs, because the system activates the audio session for it. Its tap closure is built outside the main actor, because Swift 6 traps when the audio thread calls a main-actor closure.
- **Paster** has two ways to insert text. Paste saves the clipboard, writes the text, posts ⌘V, and restores the clipboard 600 ms later unless something else changed it. Type posts one key event per character, with the character attached, and does not touch the clipboard. A second text waits until the first is typed.
- **StatusItemController** builds the menu from `MenuItem`s, whose title, checkmark, and visibility are closures. One `refresh()` updates them all.

## iPhone app and keyboard

`iOS/project.yml` makes an Xcode project with XcodeGen. The app links PhonoCore and PhonoKit and always uses a Phonon server.

A keyboard extension cannot use the microphone, and iOS does not let an app turn it on from the background. The one exception is a walkie-talkie, so the app records through the PushToTalk framework:

1. `TalkChannel` joins one channel, with nobody else on it, when the user turns on the Talk button. iOS keeps the channel joined and shows a Talk button in the status bar or the Dynamic Island.
2. A Talk press launches the app in the background if needed, and the system activates the audio session. `Dictation` opens the Recorder and starts a clip.
3. When the press ends, the app transcribes the clip and writes the state and the text to the `group.io.github.eriko13.phono` App Group defaults, then posts a `changed` Darwin notification. The keyboard reads them and inserts the text.

The keyboard is drawn with UIKit, like Apple's: letters, numbers, and symbols pages, shift and caps lock, and capitals where the text field asks for them. `KeyboardView` tracks each finger by hand, so a character is typed when its finger lifts or when the next finger lands, as fast typing needs. Holding the space bar turns the keys into a trackpad that moves the cursor left and right; iOS gives a keyboard no way to move it up or down.

The bar above the keys shows suggestions. `Suggester` gets completions and fixes from iOS's spell checker (`UITextChecker`), and text replacements and contact names from `UILexicon`. Space applies the highlighted fix, and delete right after undoes it. After a space, `NextWords` predicts the next word: a starter list in `next-words.txt`, plus the word pairs the user types, saved in the App Group container. The rules that need no UIKit, in `Typing` and `NextWords`, are in PhonoCore with tests.

`KeyboardLink` in `iOS/Shared` is the whole protocol, compiled into both targets. The keyboard needs Full Access to use the App Group. It does not touch the network.

## Model

`Scripts/download-model.sh` puts the model in `~/Library/Application Support/Phono/Phonon-2-CoreML`. The script pins one Hugging Face revision and checks SHA-256 sums. The app never uses the network. `Model.files` in PhonoCore lists the files the app needs; keep it in step with the script.

## Settings

All settings are in the `io.github.eriko13.phono` defaults domain. The app and the bare CLI binary both read from it. The CLI names the suite explicitly, because it has no bundle identifier.
