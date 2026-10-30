#!/bin/bash
# capall.sh  — wait for ko batch, then capture the chosen set per UI language
U=E4622EF4-3B8B-43F0-8BF4-E7EE36D24539; B=com.roro.futurevoice.dev
D=/private/tmp/claude-502/-Users-eunggyuelee-FutureVoice/063bf355-e574-4ac9-9ca0-ee23398cfd24/scratchpad/asc/raw
while pgrep -f "marketing/capture.sh" >/dev/null; do sleep 3; done
shot(){ # dir lang locale name [extra args...]
  local dir=$1 lang=$2 loc=$3 name=$4; shift 4
  mkdir -p $D/$dir
  xcrun simctl terminate $U $B 2>/dev/null
  xcrun simctl launch $U $B -capture $name -AppleLanguages "($lang)" -AppleLocale $loc "$@" >/dev/null
  sleep ${WAIT:-8}; xcrun simctl io $U screenshot $D/$dir/$name.png >/dev/null 2>&1 || echo FAIL $dir $name
}
SET="transcript call-focus call-coach composer-box watchtab-sky talkdetail speech-result activity-week progress"
for pair in "ja ja ja_JP" "de de de_DE" "fr fr fr_FR" "es es es_ES" "zh-Hant zh-Hant zh_TW" "zh-Hans zh-Hans zh_CN"; do
  set -- $pair; for n in $SET; do shot $1 $2 $3 $n; done; echo "done $1"
done
# English storefront: learning Japanese
for n in transcript-ja talkdetail-ja shadow-ja wordcard-ja speech speech-result call-focus composer-box watchtab-sky activity-week progress home; do
  shot en-ja en en_US $n -futurevoice.targetLanguage ja; done; echo "done en-ja"
# Korean re-shoots that were mid-load
WAIT=15 shot ko ko ko_KR say-again-reading
WAIT=15 shot ko ko ko_KR shadow
echo ALLDONE
