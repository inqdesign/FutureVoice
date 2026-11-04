-- Speech challenges name their CATEGORY and carry an INTRO (founder,
-- 2026-11-04: "each challenge should say what it is and what to keep in
-- mind, like: be the show host").
--
-- category: a key the app names in the learner's language ("show_host",
-- "famous_speech", "movie_scene", "acceptance", "product_launch"); an
-- unknown key draws nothing. intro: one or two sentences per APP language
-- ({"ko": ..., "en": ...}), because it is coaching, not material; the app
-- reads the learner's language, then English. Both null/empty on every
-- challenge before this, and older builds ignore both columns.
--
-- (Category was first folded into 20261027131000 after that version had
-- already run in production, so it never ran. It lives here.)

alter table public.speech_challenges add column if not exists category text;
alter table public.speech_challenges add column if not exists intro jsonb not null default '{}'::jsonb;

drop function if exists public.speech_challenge_list(text);
create function public.speech_challenge_list(p_language text)
returns table (
  id uuid, title text, genre text, body text, summary text,
  key_terms jsonb, sources jsonb, target_seconds int, published_at timestamptz,
  retired_at timestamptz,
  entrants int, top_score int, my_best int, my_rank int, my_attempts int,
  top_three jsonb, attempts int, category text, intro jsonb
)
language sql stable security definer set search_path = public as $$
  with ranked as (
    select e.challenge_id, e.user_id, e.best_score, e.attempts,
           rank() over (partition by e.challenge_id order by e.best_score desc) as r
    from speech_challenge_entries e
    join speech_challenges c on c.id = e.challenge_id
    where c.language = p_language
  )
  select c.id, c.title, c.genre, c.body, c.summary, c.key_terms, c.sources,
         c.target_seconds, c.published_at,
         case when c.is_active then null else coalesce(c.retired_at, c.published_at) end,
         (select count(*)::int from ranked x where x.challenge_id = c.id),
         (select max(x.best_score) from ranked x where x.challenge_id = c.id),
         me.best_score, me.r::int, me.attempts,
         coalesce((
           select jsonb_agg(jsonb_build_object('display_name', t.display_name, 'avatar', t.avatar_jpeg)
                            order by t.best_score desc, t.best_at)
           from (
             select p.display_name, p.avatar_jpeg, e.best_score, e.best_at
             from speech_challenge_entries e
             join speech_challenge_profiles p on p.user_id = e.user_id
             where e.challenge_id = c.id
             order by e.best_score desc, e.best_at
             limit 3
           ) t
         ), '[]'::jsonb),
         (select coalesce(sum(x.attempts), 0)::int from ranked x where x.challenge_id = c.id),
         c.category, c.intro
  from speech_challenges c
  left join ranked me on me.challenge_id = c.id and me.user_id = auth.uid()
  where c.language = p_language
  order by c.is_active desc, c.published_at desc;
$$;

revoke all on function public.speech_challenge_list(text) from public;
grant execute on function public.speech_challenge_list(text) to authenticated;

update public.speech_challenges
   set category = 'show_host',
       intro = '{"en": "You’re a home-shopping host, live on air, selling one night cream. Look straight into the camera, show off your own skin with confidence, and talk as if the phones won’t stop ringing.", "ko": "생방송 홈쇼핑 쇼호스트가 되어 나이트 크림 하나를 파는 장면이에요. 카메라를 똑바로 보고, 내 피부를 보여주듯 자신 있게, 주문 전화가 쏟아지는 것처럼 말해 보세요.", "ja": "生放送のテレビ通販で、ナイトクリームをひとつ売り込む場面です。カメラをまっすぐ見て、自分の肌を見せるように自信を持って、注文の電話が鳴りやまない勢いで話してみましょう。", "de": "Du moderierst live im Teleshopping und verkaufst eine Nachtcreme. Schau direkt in die Kamera, zeig selbstbewusst deine eigene Haut und sprich, als würden die Telefone gar nicht mehr stillstehen.", "es": "Presentas un programa de teletienda en vivo y vendes una crema de noche. Mira directo a la cámara, presume de tu piel con seguridad y habla como si los teléfonos no pararan de sonar.", "fr": "Tu animes une émission de téléachat en direct et tu vends une crème de nuit. Regarde la caméra droit dans les yeux, montre ta peau avec assurance et parle comme si les téléphones n’arrêtaient pas de sonner.", "zh-Hant": "你是電視購物的直播主持人，要賣一款晚霜。直視鏡頭，自信地秀出自己的皮膚，講得像訂購電話響個不停一樣。", "zh-Hans": "你是电视购物的直播主持人，要卖一款晚霜。直视镜头，自信地展示自己的皮肤，讲得像订购电话响个不停一样。"}'::jsonb
 where id = '5beec000-0000-4000-8000-000000000020';
