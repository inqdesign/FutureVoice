# App Store search optimization (ASO)

Stage: approved by the founder 2026-11-14 and committed. Goes to App Store Connect with the next submission (after 1.3.4).
Request (founder, 2026-11-14): check the listing, optimize it for the next version, run it as its own project.

## Where the store stands (2026-11-14)
- Live: 1.3.3. Ratings: US 3, KR 6, JP 1, DE 2.
- 1.3.4 (143): WAITING_FOR_REVIEW with the old text and the new Korean screenshots (G-set, see `../2026-11-11-asc-first-three`).
- Name and subtitle are locked until a new version is being prepared.

## Done: text for the next version
`scripts/asc-submit.py <version> <build> --metadata-only` prints what would change. It goes out with the next submission.

| Locale | Change |
|---|---|
| en-US / en-GB | keywords: + learn, talk, chinese; − shadowing, fluent. Description: languages line, AI tutor voice, Tutor, Pronunciation |
| ko | keywords: − 이탈리아어 (not offered), − 음성복제; + 아이엘츠, 영어발음. Description: same additions, every "—" removed |
| de-DE | name "Sprachen lernen" (was "Sprechen üben"), subtitle "Englisch sprechen üben mit KI", keywords + Deutsch, Sprache |
| es-ES / es-MX | name "Aprender idiomas" (was "Habla con tu yo fluido"), subtitle "Habla inglés con IA y tu voz", keywords − italiano, + chino, tutor, practicar |
| fr-FR | name "apprendre une langue" (was "parle couramment"), subtitle "Parler anglais avec l’IA", keywords + chinois, cours, langues, IA |
| zh-Hans / zh-Hant | name ends 学外语 / 學外語 (was 对话 / 對話), keywords swap bare 外语 for 学日语 / 學日文 |
| ja | unchanged |

Rules used: no word repeated between name, subtitle and keywords of one locale; no language the app does not offer; singular forms.

## Open
1. Founder: read the new names (de, es, fr, zh). They replace the "fluent self" line with the searched term. `git checkout` of the `name.txt` / `subtitle.txt` files restores the old ones.
2. Native read of the de / es / fr / zh names and subtitles. Not done.
3. Descriptions in de, es, fr, ja, zh still lack the AI tutor voice, Tutor and Pronunciation paragraphs (de and fr are at ~3,960 of 4,000 characters, so something has to go to make room).
4. English screenshots: the live English set still has a text-only second shot and Korean text inside the screens. The Korean G-set needs an English sibling, then the other languages.
5. Screenshot captions carry no searched words ("Always ready", "Your textbook").
6. Ratings: the prompt already fires after a 3-minute call (20 min total, 3 days) and at the end of the free-minutes report. Check `review_requested` counts in PostHog before changing the bars.
7. Not started: in-app events for the daily speech challenge, custom product pages per target language, a screenshot-order test.
8. `docs/APPSTORE_METADATA.md` still shows an old name and subtitle.

## Measure
After the version with this text is live for two weeks: App Store Connect → Analytics → Sources → App Store Search, impressions and conversion per storefront, against the two weeks before.
