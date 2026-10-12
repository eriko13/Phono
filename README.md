<p align="center"><img src="Assets/icon.png" width="128" height="128" alt="Phono icon"></p>

<h1 align="center">Phono</h1>

Dictation for macOS that runs entirely on your Mac. Hold ⌥ Option, speak, and let go. The text is typed where your cursor is.

Phono uses [Phonon-2](https://huggingface.co/FermionResearch/Phonon-2), a 164 MB English speech model. Audio never leaves your computer.

## Requirements

- A Mac with Apple silicon, macOS 15 or later
- Xcode Command Line Tools: `xcode-select --install`
- Python 3.10 or later: `brew install python@3.12`

## Install

```sh
git clone https://github.com/eriko13/Phono.git
cd Phono
./Scripts/install.sh
```

The script installs the speech engine, builds Phono, copies it to `/Applications`, and opens it. Then:

1. Allow microphone access.
2. Allow Phono in **System Settings › Privacy & Security › Accessibility**. Phono needs this to see the Option key and to paste.
3. Wait until the menu-bar icon changes from ⌛ to a waveform. The first start can take a minute.

To update, run `git pull` and `./Scripts/install.sh` again. macOS treats each build as a new app, so remove the old Phono entry from the Accessibility list and allow the new one.

## Use

Hold **⌥ Option** and speak. Release it, and the text appears in the active app. Phono puts back whatever was on your clipboard.

Option is also part of other shortcuts, such as ⌥←. If you press another key or click while you hold Option, Phono discards the recording, so those shortcuts work as usual.

Settings are in the menu-bar menu:

- **Mode**: hold to talk, or press once to start and again to stop.
- **Shortcut**: ⌥ Option, Right ⌥ Option, fn, or a key combination such as ⌃⌥Space. If you choose fn, set **Keyboard › Press 🌐 key to** to **Do Nothing**.
- **Paste into active app**: turn off to only copy the text.
- **Recent**: your last 10 transcripts. Click one to copy it again.

### More settings

These have no menu item. Set them in Terminal, then quit and reopen Phono.

```sh
# Names and terms to recognize better (up to 25)
defaults write io.github.eriko13.phono hotwords "Ada, Quillon"

# The local port of the engine (default 8178)
defaults write io.github.eriko13.phono enginePort 8178

# A fermion binary in a non-standard place
defaults write io.github.eriko13.phono enginePath ~/bin/fermion
```

### Command line

```sh
/Applications/Phono.app/Contents/MacOS/phono transcribe meeting.wav
/Applications/Phono.app/Contents/MacOS/phono status
```

`transcribe` reads wav, flac, ogg, and aiff files. Phono must be running.

## Troubleshooting

| Problem | Fix |
|---|---|
| The icon shows a crossed-out waveform | The engine did not start. Choose **Open Engine Log** in the menu. |
| Holding Option does nothing | Allow Phono in Accessibility. After a rebuild, remove the old entry first. |
| The text is copied but not pasted | The same Accessibility fix. |

## Uninstall

```sh
rm -rf /Applications/Phono.app ~/Library/Application\ Support/Phono ~/Library/Logs/Phono
defaults delete io.github.eriko13.phono
```

The engine keeps its model download in its cache folder, usually under `~/.cache`.

## Development

```sh
swift build            # the app and CLI
swift test             # tests for PhonoCore
./Scripts/bundle.sh    # build/Phono.app
```

[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) explains how the parts fit together. Pull requests are welcome. CI must pass.

## License

Phono is MIT licensed. Phonon-2 is CC-BY-4.0, by FermionResearch, based on NVIDIA's parakeet-tdt-0.6b-v3. Phono does not include the model; the setup script downloads it.
