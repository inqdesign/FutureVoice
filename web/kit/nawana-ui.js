/* nawana UI kit — entry point. One script tag on any page:
 *   <script type="module" src="/kit/nawana-ui.js"></script>
 * The base (fonts, strings, the mosaic, the phone, the screen base class) lives in core.js;
 * each screen in screens/<name>.js. See core.js for the attributes every screen takes. */
import { NwFutureself, NwPhone, NwBubble, NwFix } from "./core.js";
import { NwCall } from "./screens/call.js";
import { NwHome } from "./screens/home.js";
import { NwSpeech } from "./screens/speech.js";
import { NwBook } from "./screens/book.js";
import { NwWords } from "./screens/words.js";
import { NwProgress } from "./screens/progress.js";
import { NwRing } from "./screens/ring.js";
import { NwSayAgain } from "./screens/sayagain.js";
import { NwWatch } from "./screens/watch.js";
import { NwShadow } from "./screens/shadow.js";
import { NwRoutine } from "./screens/routine.js";
import { NwPeople } from "./screens/people.js";
import { NwReview } from "./screens/review.js";
import { NwBookPage } from "./screens/bookpage.js";
import { NwWeeklyTest } from "./screens/weeklytest.js";
import { NwWeekReport } from "./screens/weekreport.js";

for (const [name, cls] of [["nw-futureself", NwFutureself], ["nw-phone", NwPhone], ["nw-bubble", NwBubble], ["nw-fix", NwFix],
  ["nw-call", NwCall], ["nw-home", NwHome], ["nw-speech", NwSpeech], ["nw-book", NwBook], ["nw-words", NwWords], ["nw-progress", NwProgress], ["nw-ring", NwRing], ["nw-sayagain", NwSayAgain], ["nw-watch", NwWatch], ["nw-shadow", NwShadow], ["nw-routine", NwRoutine], ["nw-people", NwPeople], ["nw-review", NwReview], ["nw-bookpage", NwBookPage], ["nw-weeklytest", NwWeeklyTest], ["nw-weekreport", NwWeekReport]])
  if (!customElements.get(name)) customElements.define(name, cls);

export * from "./core.js";
export { NwCall, NwHome, NwSpeech, NwBook, NwWords, NwProgress, NwRing, NwSayAgain, NwWatch, NwShadow, NwRoutine, NwPeople, NwReview, NwBookPage, NwWeeklyTest, NwWeekReport };
