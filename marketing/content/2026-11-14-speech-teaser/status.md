# Speech app teaser

Stage: draft with sound, waiting for the founder (2026-11-14)

## Request
"스피치 어론 앱을 티징하는 영상… 로고, 그리고 일러스트들을 보여주면서 사람들을 궁금하게."
Storyboard (storyboard.png) shown first; founder: "재밌을껏 같은데?"

## What was made
- teaser.html: 9:16, 18 s, one clock render(t) on a 100 BPM grid (0.6 s a beat) so a track can go under it.
- teaser_silent.mp4: recorded with step-record.mjs (command in the file's header).
- media/: copies of SpeechApp/Illustrations with the cut-out edge cleaned for black (the originals keep a
  paper-coloured 1–2 px rim that showed as a light outline; founder: "누끼딴게 어두운 배경에 티가 많이나").
  Small interior holes (paper the cut-out tool removed) are filled with paper colour, so the flight attendant's
  patterned blouse reads plain white now. Script: scratchpad defringe.py (erode 2 px, rim colour from inside, alpha blur 0.8).
- Lines are the real first words of live challenges. 002C is the weatherman (not a detective). The award winner
  (0024, Michelle Yeoh's real speech) says nothing.

## Open
- App name on the end card ("어론" = Aloud?), now "Coming soon" only.
- End line language (English "Your turn.").

## 2026-11-14 the sound is the readings
Founder: "오디오는 이미 너가 가지고 있잖아 … 샘플오디오 … TTS?" = the challenges' own fluent listening readings
(speech_listen_audio, R2), not music. build_timeline.py downloads nothing; media/voice/ holds the 10 WAVs + rows.json.
Each person says their real opening in their reading's voice and is cut 0.13 s into the next word; the words go up
as they are said (timeline.js). The award winner (Michelle Yeoh's speech) stays silent. Then everyone talks at once
(-7.5 dB each) and each light out stops that voice. End card in silence. teaser.mp4, 25.5 s, AAC.
The beat grid and media/track from the founder's song are no longer used (track.wav is now the voice cut).

## 2026-11-14 founder round 3
- Opening: synthesized mic switch-on (click, hum, faint feedback) at 0.25 s, then "Ahem." at 1.05 s in the readings'
  female voice (Cartesia sonic-3.6, media/ahem/take1–6: Ahem ×2, Ahem ahem, Hm-hm, Mm-hmm, Ehem; AHEM=takeN to swap).
- The mic boils like the creator cut (three wobble filters, six swaps a second).
- Voices fade (cosine, 0.2 s at each cut; 0.9 s from each light out in the crowd, the last three 1.5 s).
- The award winner speaks ("Thank you.") like the rest (founder: "오바좀 하지마").
- Lines read like the app's read-along: whole line at 28%, the word being said in blue, said words full.
- Ending: the last people go, the mic finishes on black while the voices fade, cream comes up, "Your turn.".
  teaser.mp4 27.2 s. Level falls smoothly from 20 s to silence at 24 s (measured per 0.5 s).
