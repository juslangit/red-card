# Audio sources

Every sound is CC0 (no attribution needed, commercial use allowed), fetched with the
`sfx` CLI. Raw downloads land in `_downloads/` (gitignored); the files the game loads
are cut from them with ffmpeg and saved as 48 kHz 16-bit PCM WAV or Ogg.

| File | What it is | Source |
|---|---|---|
| `whistle.wav` | a single referee's peep | Referee whistle sound by Rosa-Orenes256 (#538422), CC0 — via Referee For Fun |
| `whistle_short.wav`, `whistle_firm.wav`, `whistle_long.wav` | stop play, a firm foul whistle, the end of a half | metal whistle by strongbot (#568995), CC0 — blasts at 0.77 s, 3.68 s, 12.72 s |
| `kick_1..3.wav` | boot on ball | Soccer Ball Kick by bittermelonheart (#555042), soccer ball kick 2 by Luisa_Sanchez (#816823), CC0 |
| `steps/grass_1..5.wav` | the referee's footsteps | Footsteps Grass by HenKonen (#682128), CC0 |
| `crowd/football_ambience.mp3` | a small ground's bed | Norwegian football match ambience by Vogyik (#868982), CC0 — via Referee For Fun |
| `crowd/small_walla.mp3` | a handful of people talking | Small Crowd Walla by IENBA (#653920), CC0 — via Referee For Fun |
| `crowd/stadium_bed.ogg` | a big ground's bed | CRWDReac-SOCCER Millerntor Stadium Crowd Reaction by itmightgetloud (#829453), CC0 — first 45 s |
| `crowd/goal_chant.ogg` | a stadium after a goal | Goal! by blaukreuz (#189821), CC0 — first 30 s |
| `crowd/cheer.wav`, `crowd/goal_roar.mp3` | cheers | Crowd Cheer by FoolBoyMedia (#397434); Crowd Cheer 7 by Krizin (#651644), CC0 — via Referee For Fun |
| `crowd/groan.wav`, `crowd/oooh.mp3`, `crowd/boo.mp3` | the ground disagreeing | ShangusBurger (#764253); Crowd Oooh (#324890); Julien_Matthey (#557189), CC0 — via Referee For Fun |
| `ui/*.ogg` | menu sounds | Kenney interface-sounds, CC0 — via Referee For Fun |

    sfx get 682128 --name steps_grass
    sfx get 555042 --name kick ; sfx get 816823 --name kick2
    sfx get 568995 --name metal_whistle
    sfx get 829453 --name stadium_reaction ; sfx get 189821 --name goal_chant
| `contact/contact_1.wav` | Body contact in a tackle | https://freesound.org/people/insanity54/sounds/276600/ |
| `contact/contact_2.wav` | A lighter challenge, thud on clothing | https://freesound.org/people/JonasTisell/sounds/496187/ |
| `crowd/gasp.wav` | The crowd gasping at one the referee did not give | https://freesound.org/people/HowardV/sounds/264376/ |
| `voices/shout_one.wav` | One player appealing | https://freesound.org/people/metrostock99/sounds/345083/ |
| `voices/shout_many.wav` | A team appealing together | https://freesound.org/people/khenshom/sounds/527740/ |
| `trailer/music_open.wav` | Glimmer of hope — electro-orchestral, used under the first minute | https://freesound.org/people/xkeril/sounds/671962/ |
| `trailer/music_close.flac` | Epic Synth/Orchestral Music — used under the second half | https://freesound.org/people/Bertsz/sounds/545459/ |
