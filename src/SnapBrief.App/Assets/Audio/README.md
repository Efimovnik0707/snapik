# Bundled interface sounds

Three short sounds picked from the set delivered with the first test round (`tasks/handoff-001/sounds/`,
`SOUNDS.md`, 12 September 2026). Per that note the set comes from Pixabay and Freesound under the
Pixabay Content License / CC0 1.0, both of which permit copying, modification, commercial use and
redistribution without attribution.

Provenance is incomplete: the direct source links (URL, author, id) for these three files were not
delivered with the set and are to be written in here once they arrive. Until then the licence claim
rests on `SOUNDS.md` alone, which is below the standard the previous camera recordings were held to.

The files ship as ordinary content next to the executable (`Assets\Audio\*.mp3` in the csproj), because
`MediaPlayer` opens files rather than `pack://application` resources. They are played by
`UiSoundService`, each at a gain of its own on top of the `SoundVolume` preference.

| File | Where it plays | Gain | Size | SHA-256 |
|---|---|---|---|---|
| `shutter-2-050s.mp3` | the moment of capture | 1.0 | 15 882 B | `A479D066076503EE27194A3C7FF0B2CB7F07DF55E988D96BB5BB1D6C0B3AF82D` |
| `click-tiny-005s.mp3` | pointing at a capture in the strip | 0.25 | 1 536 B | `8D81CBFE9A05B30DA6730F03C1976E59143CB425F8FA4D9E4129DF6F65643B7A` |
| `notify-soft-040.mp3` | the package went to the clipboard | 0.7 | 34 272 B | `C13DA61F3E5BCD79CE3E8785715970EF8D09B2EDCD5F956FEBC6D83E6A759827` |

The files are byte-identical to the delivered ones: nothing was re-encoded or edited here. The smoke run
checks that all three are shipped next to the assembly, are not empty and start as an MP3 stream
(`ID3` tag or a frame sync); none of them was auditioned by the agent.

The camera recordings this replaced (`camera-shutter.wav`, `camera-dial-click.wav`, CC0 from Freesound,
users `mmaruska` 167556 and `Headphaze` 696760) were removed together with `CaptureFeedbackSound`; their
provenance stays in the git history of this file.
