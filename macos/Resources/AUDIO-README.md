# Bundled camera feedback recordings

Copied as-is from `src/SnapBrief.App/Assets/Audio/` (SPEC-DELTA-2.md §6, SPEC-DELTA-2B.md §E2).
Both files are edits of real camera recordings published under the Creative Commons Zero 1.0
Universal dedication. CC0 permits copying, modification, commercial use, and redistribution
without attribution. Attribution is retained here so the source and edit remain auditable. Full
provenance: `src/SnapBrief.App/Assets/Audio/README.md`.

## `camera-shutter.wav`

- Source: [Nice Camera click.wav](https://freesound.org/people/mmaruska/sounds/167556/) by Freesound user `mmaruska`, sound ID 167556. License: CC0 1.0 Universal.
- Edit: 44.1 kHz, 16-bit PCM, mono; ~340 ms.
- Bundled file SHA-256: `57C7D8AAEA24E1350A72C76BE3D26937600DDEBD1FB6F559A70D9A2E51D1B0E5`.

## `camera-dial-click.wav`

- Source: [INSTAX CAMERA - Mechanical wheel, ratchet.WAV](https://freesound.org/people/Headphaze/sounds/696760/) by Freesound user `Headphaze`, sound ID 696760. License: CC0 1.0 Universal.
- Edit: 44.1 kHz, 16-bit PCM, mono; ~150 ms.
- Bundled file SHA-256: `9A5D6C9019548C410048C5EAC3BDE1E314B31F43D6A1A6E9F13419C203B66666`.

## Usage on macOS

`CaptureFeedbackSound.capture(enabled:)` plays `camera-shutter.wav` right after a capture is
committed to the stack; `CaptureFeedbackSound.tick(enabled:)` plays `camera-dial-click.wav` on
stack-card hover/scroll, throttled to 170 ms between ticks and suppressed for 400 ms after a
shutter sound. Both are gated by the `PlaySounds` setting (default on). This file is excluded from
the app bundle (`project.yml`'s `excludes: ["Resources/**/*.md"]`); only the two `.wav` files are
copied into `Contents/Resources`.
