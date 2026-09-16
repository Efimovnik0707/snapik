# Bundled interface sounds

Copied byte for byte from `src/Snapik.App/Assets/Audio/` (SPEC-DELTA-3 §1.5 G-11). Nothing was
re-encoded or edited here, and none of them was auditioned by the agent. Full provenance, the
measurements behind the gains and the story of what they replaced:
`src/Snapik.App/Assets/Audio/README.md`.

The set comes from Pixabay and Freesound under the Pixabay Content License / CC0 1.0, both of which
permit copying, modification, commercial use and redistribution without attribution. Attribution is
kept here so the source stays auditable.

| File | Where it plays | Gain | Author | Pixabay id | Size |
|---|---|---|---|---|---|
| `shutter-1-039s.mp3` | the moment of capture | 0.6 | kauasilbershlachparodes | 494024 | 12 538 B |
| `click-tiny-005s.mp3` | pointing at a capture in the strip | 0.25 | denielcz | 463065 | 1 536 B |
| `notify-soft-040.mp3` | the package went to the clipboard ("Копировать пакет") | 0.7 | Universfield | 493469 | 34 272 B |

## Usage on macOS

`App/UiSoundService.swift` plays all three, each at the gain above on top of the `SoundVolume`
preference (0…100, default 40) and gated by `PlaySounds` (default on). The tick is throttled to
170 ms between ticks and suppressed for 400 ms after a shutter. The files live in
`Sources/SnapikMac/Resources/Audio/`, are listed in `Package.swift` and are picked up by the Xcode
target through `project.yml`'s `Sources/SnapikMac` path. This note lives outside that path, in
`macos/Resources/`, so it ships with neither build.

The smoke run checks that all three are shipped, are not empty and start as an MP3 stream
(`UiSoundService.verifyAssets`), and `scripts/ci-smoke.sh` checks that the two camera WAVs they
replaced are gone from the bundle.

The camera recordings this replaced (`camera-shutter.wav`, `camera-dial-click.wav`, CC0 from
Freesound, users `mmaruska` 167556 and `Headphaze` 696760) left together with
`CaptureFeedbackSound`; their provenance stays in the git history of this file.
