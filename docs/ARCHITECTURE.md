# Architecture

Phono is one Swift package with two targets and no dependencies.

| Target | Contents |
|---|---|
| `PhonoCore` | Foundation only, so it builds and tests on any platform: hotkey presets and the lone-modifier state machine, settings, the engine HTTP client, WAV encoding, and text clean-up. |
| `phono` | The macOS app and CLI in one binary. With arguments it runs as a CLI; without, as a menu-bar app. |

## Flow

```
HotkeyManager ─► DictationController ─► Recorder (16 kHz mono)
                        │
                        ├─► TranscriptionClient ─► fermion serve phonon-2 (127.0.0.1)
                        │
                        └─► Paster (clipboard + ⌘V) and HUD
```

- **EngineController** starts `fermion serve phonon-2` at launch and keeps it running, because loading the model takes 10–40 s. If a server already answers on the port, Phono uses it.
- **HotkeyManager** registers key combinations with Carbon. A lone modifier (⌥, fn) cannot be registered that way, so it watches global key events instead, which needs Accessibility. `ModifierTriggerState` decides what counts as a press: if another key, modifier, or click joins, the press is interrupted and the audio discarded.
- **DictationController** records from the first instant of a lone-modifier press, but shows the HUD and plays the sound only after 250 ms, so quick taps and ⌥← stay invisible.
- **Recorder** converts to 16 kHz mono on the audio thread. Its tap closure is built outside the main actor, because Swift 6 traps when the audio thread calls a main-actor closure.
- **Paster** saves the clipboard, writes the text, posts ⌘V, and restores the clipboard 600 ms later unless something else changed it.
- **StatusItemController** builds the menu from `MenuItem`s, whose title, checkmark, and visibility are closures. One `refresh()` updates them all.

## Settings

All settings are in the `io.github.eriko13.phono` defaults domain. The app and the bare CLI binary both read from it. The CLI names the suite explicitly, because it has no bundle identifier.
