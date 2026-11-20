# Copy: nawana, now on Android (2026-11-08-android-launch)

One 1080×1350 card (ko + en) and one Threads post (ko + en). No em dashes anywhere.
Strings below are final; lift them as written. `\n` = the line break in the pixel title.

## 01 · the card (ko)

title (pixel, Galmuri14):  안드로이드에도\n나와나가 왔어요
body (sans, one line; break after the comma if it must wrap):
    아이폰과 같은 앱 그대로, 내 목소리로 말하는 유창한 나와 통화해요.
bottom block:
    wordmark:  nawana
    where:     Google Play
    site:      nawana.app
    free:      첫 20분은 무료예요
screen: none (direction B). `nw-futureself` pill, light palette, speaking, full light.
sticker (OPTIONAL, `nw-bubble who="self"`, stays English on both cards, it's material):
    Hey! So what are we talking about today?
alt (ko): 나와나 안드로이드 출시 이미지. "안드로이드에도 나와나가 왔어요"라는 제목 아래 파란 픽셀 모자이크가 켜진 알약 모양이 있고, 맨 아래에 Google Play, nawana.app, 첫 20분은 무료라는 안내가 있어요.

## 01 · the card (en)

title (pixel, Geist Pixel):  Now on\nAndroid
body (sans, one line):
    The same app as on iPhone. Talk with your fluent self, in your own voice.
bottom block:
    wordmark:  nawana
    where:     Google Play
    site:      nawana.app
    free:      Your first 20 minutes are free
screen: as ko.
sticker (OPTIONAL): Hey! So what are we talking about today?
alt (en): nawana's Android launch card: the title "Now on Android" above a glowing blue pixel-mosaic pill, with Google Play, nawana.app and "Your first 20 minutes are free" at the bottom.

## Threads post (ko)

    나와나가 이제 안드로이드에도 나왔어요.
    아이폰과 같은 앱 그대로, 내 목소리를 한 번 복제하면 유창해진 나와 통화하며 언어를 배울 수 있어요.
    기다려 주신 분들, 고마워요. Google Play에서 받아 보세요.
    https://play.google.com/store/apps/details?id=com.roro.futurevoice

topic tag: 영어회화

## Threads post (en)

    nawana is on Google Play now.
    It's the same app as on iPhone: clone your voice once, then learn a language by talking with your fluent self, who sounds just like you.
    Thanks for waiting. Get it here:
    https://play.google.com/store/apps/details?id=com.roro.futurevoice

topic tag: LanguageLearning

## Not used

Community series entry: none (news, not a feature-series piece; per brief).
Instagram caption: none (Threads only, lead decision in status.md).

## Open questions for the lead

1. Free 20 minutes on Android: Android's `AccountStatus.FREE_GRANT_SECONDS = 1200` and
   `BillingConfig` reads the same server `free_talk_seconds` (default 1200), so it looks
   right. The signup grant itself is server-side; reviewer to confirm it lands on a
   Google-signed-in account before the `free` line stays.
2. "아이폰과 같은 앱" / "same app as on iPhone" names the iPhone once, as the brief's
   Threads intent allows. If the founder reads that as a comparison, the fallbacks are
   ko body `내 목소리로 말하는 유창한 나와 통화해요.` and en body
   `Talk with your fluent self, in your own voice.` (post line 2 drops its first clause
   the same way).
3. Play link not opened by me (package from the brief). Check it resolves before posting.
