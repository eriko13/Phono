# Architecture

Phono is one Swift package with two targets. Its one dependency is [phonon-coreml](https://github.com/fermionresearch/phonon-coreml), Fermion Research's runner for Phonon-2 on Core ML.

| Target | Contents |
|---|---|
| `PhonoCore` | Foundation only, so it builds and tests on any platform: hotkey presets and the lone-modifier state machine, settings, where the model lives, and text clean-up. |
| `phono` | The macOS app and CLI in one binary. With arguments it runs as a CLI; without, as a menu-bar app. |

## Flow

```
HotkeyManager ─► DictationController ─► Recorder (16 kHz mono)
                        │
                        ├─► SpeechModel ─► Phonon-2 (Core ML, Neural Engine)
                        │
                        └─► Paster (clipboard + ⌘V) and HUD
```

- **SpeechModel** loads Phonon-2 at launch on a background queue and keeps it in memory. On the first launch, Core ML compiles the model for the Mac's Neural Engine, which takes a minute or two; later launches load in about a second. Each clip runs on one serial queue.
- **HotkeyManager** registers key combinations with Carbon. A lone modifier (⌥, fn) cannot be registered that way, so it watches global key events instead, which needs Accessibility. `ModifierTriggerState` decides what counts as a press: if another key, modifier, or click joins, the press is interrupted and the audio discarded.
- **DictationController** records from the first instant of a lone-modifier press, but shows the HUD and plays the sound only after 250 ms, so quick taps and ⌥← stay invisible.
- **Recorder** converts to 16 kHz mono on the audio thread. Its tap closure is built outside the main actor, because Swift 6 traps when the audio thread calls a main-actor closure.
- **Paster** saves the clipboard, writes the text, posts ⌘V, and restores the clipboard 600 ms later unless something else changed it.
- **StatusItemController** builds the menu from `MenuItem`s, whose title, checkmark, and visibility are closures. One `refresh()` updates them all.

## Model

`Scripts/download-model.sh` puts the model in `~/Library/Application Support/Phono/Phonon-2-CoreML`. The script pins one Hugging Face revision and checks SHA-256 sums. The app never uses the network. `Model.files` in PhonoCore lists the files the app needs; keep it in step with the script.

## Settings

All settings are in the `io.github.eriko13.phono` defaults domain. The app and the bare CLI binary both read from it. The CLI names the suite explicitly, because it has no bundle identifier.
