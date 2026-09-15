# Bundled interface sounds

Three short sounds picked from the set delivered with the test rounds (`tasks/handoff-002/sounds/`,
`SOUNDS.md`). Per that note the set comes from Pixabay and Freesound under the Pixabay Content
License / CC0 1.0, both of which permit copying, modification, commercial use and redistribution
without attribution.

Provenance is per file below. The names of the delivered originals carry the author and the id on
Pixabay, and a sound is found by that id: `https://pixabay.com/sound-effects/search/<id>/`. The exact
page URL cannot be derived from the file name alone, so the author and the id are given instead.

| File | Original in `tasks/handoff-002/sounds/` | Author | Pixabay id |
|---|---|---|---|
| `shutter-1-039s.mp3` | `kauasilbershlachparodes-chutter-click-494024.mp3` | kauasilbershlachparodes | 494024 |
| `click-tiny-005s.mp3` | `denielcz-immersivecontrol-button-click-sound-463065.mp3` | denielcz | 463065 |
| `notify-soft-040.mp3` | `universfield-new-notification-040-493469.mp3` | Universfield | 493469 |

The files ship as ordinary content next to the executable (`Assets\Audio\*.mp3` in the csproj), because
`MediaPlayer` opens files rather than `pack://application` resources. They are played by
`UiSoundService`, each at a gain of its own on top of the `SoundVolume` preference.

| File | Where it plays | Gain | Size | SHA-256 |
|---|---|---|---|---|
| `shutter-1-039s.mp3` | the moment of capture | 0.6 | 12 538 B | `9F5EA1ECE0FC14A6031E13087B7E720A874D064C12C68FA4906E98BFBBF20E20` |
| `click-tiny-005s.mp3` | pointing at a capture in the strip | 0.25 | 1 536 B | `8D81CBFE9A05B30DA6730F03C1976E59143CB425F8FA4D9E4129DF6F65643B7A` |
| `notify-soft-040.mp3` | the package went to the clipboard | 0.7 | 34 272 B | `C13DA61F3E5BCD79CE3E8785715970EF8D09B2EDCD5F956FEBC6D83E6A759827` |

Why the shutter sits at a gain of 0.6. The capture was reported as loud and doubled, and the numbers
say the second sound was most of it. Measured with `ffmpeg volumedetect` over the whole file:

| File | mean | max | length |
|---|---|---|---|
| `shutter-2-050s.mp3` (the shutter this replaced, gain 1.0) | −37.3 dB | −8.3 dB | 0.496 s |
| `notify-soft-040.mp3` (the second sound of a capture, gain 0.7) | — | −5.1 dB | 1.071 s |
| `shutter-1-039s.mp3` (this one) | −31.1 dB | −5.9 dB | 0.392 s |
| `freesound_community-iphone-camera-capture-6448` (the other candidate) | −29.1 dB | −7.0 dB | 0.624 s |

The new shutter is about 6 dB hotter than the old one, so the gain has to give that back: 0.6 together
with the new default volume of 40 lands around 2 dB under the old pair, and the second sound is gone
from the capture altogether. If it is still too loud, the gain is the knob to turn (0.45 takes another
2.5 dB), not the volume preference. The other candidate was passed over because it is longer than the
400 ms of `SoundThrottle.CaptureSuppressionMilliseconds`, so a tick would come back over its tail.

The files are byte-identical to the delivered ones: nothing was re-encoded or edited here. The smoke run
checks that all three are shipped next to the assembly, are not empty and start as an MP3 stream
(`ID3` tag or a frame sync), and that the shutter that was replaced is not shipped beside them; none of
them was auditioned by the agent.

The camera recordings this replaced (`camera-shutter.wav`, `camera-dial-click.wav`, CC0 from Freesound,
users `mmaruska` 167556 and `Headphaze` 696760) were removed together with `CaptureFeedbackSound`; their
provenance stays in the git history of this file.
