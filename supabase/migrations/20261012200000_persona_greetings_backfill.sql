-- Greetings for the personas already in the pool (2026-10-12), written by
-- hand rather than generated: a curated character greets from inside the
-- situation their intro puts them in, in their own register; a published
-- learner's line takes ONE concrete detail from their own public intro (never
-- health or family history), or only their town/interests when the intro is
-- just a list. Only empty greetings are filled — an author's own line stays.
-- Rows whose intro is under the pool's 80-character bound (NOT VALID, so old
-- one-liners are still active) can't be updated at all; the app writes a
-- greeting for those the first time its map needs one.
update public.public_personas set greeting = 'Guten Morgen! Kurz vor der Runde – sagen Sie mir ehrlich: Hält der Zeitplan?' where id = '678f5980-9762-4dff-a87c-3b697f31203b' and greeting = '' and char_length(intro) between 80 and 2000;
update public.public_personas set greeting = 'Hallo! Ich komme gerade vom Amt. Haben Sie kurz Zeit?' where id = '7a9f4e27-8e39-41e9-99ee-017323005354' and greeting = '' and char_length(intro) between 80 and 2000;
update public.public_personas set greeting = 'Guten Tag! Schön, dass Sie da sind. Haben Sie fünf Minuten für mich?' where id = 'e845903f-2e1d-443e-8ae0-5b8b38b6d996' and greeting = '' and char_length(intro) between 80 and 2000;
update public.public_personas set greeting = 'Klein, Ihr Vermieter. Ist in der Wohnung alles in Ordnung?' where id = 'c7b0c884-35cc-4ff5-ad7d-e645c11ef124' and greeting = '' and char_length(intro) between 80 and 2000;
update public.public_personas set greeting = 'Ach, hallo! Gut, dass ich Sie im Treppenhaus erwische …' where id = 'cdbe1d62-e127-4685-9624-d64ee8931441' and greeting = '' and char_length(intro) between 80 and 2000;
update public.public_personas set greeting = 'Hallo, Marek, Elektriker. Haben Sie kurz Zeit? Mir fehlt da ein Satz.' where id = '36b5100e-bb77-4124-af76-8f05c622c1e7' and greeting = '' and char_length(intro) between 80 and 2000;
update public.public_personas set greeting = 'Hallo! Ich habe gerade Pause. Darf ich Sie etwas fragen?' where id = 'eab29ae6-5c92-4eec-ab92-5a0a62bf8a5e' and greeting = '' and char_length(intro) between 80 and 2000;
update public.public_personas set greeting = 'Hallo! Erzählen Sie mal – wie fühlt sich das genau an?' where id = 'fd782246-0351-4997-ba22-438176933fb5' and greeting = '' and char_length(intro) between 80 and 2000;
update public.public_personas set greeting = 'Hallo! Ich hab gerade ein neues Rezept ausprobiert – kochst du auch gern?' where id = 'd34c0924-c87d-4c65-9497-c705528cc461' and greeting = '' and char_length(intro) between 80 and 2000;
update public.public_personas set greeting = 'Hi! Ich komm gerade von der Uni. Wie läuft''s bei dir?' where id = 'c47531c2-422c-4640-8796-3680c3c30d70' and greeting = '' and char_length(intro) between 80 and 2000;
update public.public_personas set greeting = 'Hallo aus Mainz! Ich bin gerade auf dem Weg zur Kita – und du?' where id = '3297065b-0ad3-496e-b377-5de4195018ad' and greeting = '' and char_length(intro) between 80 and 2000;
update public.public_personas set greeting = 'Hallo! Ich komme gerade vom Laufen im Park. Liest du auch gern Krimis?' where id = 'e9cdcd12-e181-4e61-a846-69c465721096' and greeting = '' and char_length(intro) between 80 and 2000;
update public.public_personas set greeting = 'Hello! Come in – what can I help you with today?' where id = '7f54389d-d19a-4c27-bae9-8ed473f00cf2' and greeting = '' and char_length(intro) between 80 and 2000;
update public.public_personas set greeting = 'Hey! What can I get you? Flat white?' where id = '9cc7abbf-04fa-405a-ad54-ce89646ea849' and greeting = '' and char_length(intro) between 80 and 2000;
update public.public_personas set greeting = 'Frank, your landlord. Everything alright in the flat?' where id = '8a435c8b-677b-4d4b-8797-1ddb8d27b42e' and greeting = '' and char_length(intro) between 80 and 2000;
update public.public_personas set greeting = 'Hi! Give me three seconds – I''m still in meeting mode.' where id = '8d74edbd-8467-4b51-99e3-ef517594c783' and greeting = '' and char_length(intro) between 80 and 2000;
update public.public_personas set greeting = 'Hi, thanks for coming in! Have you got a few minutes?' where id = 'd3c65d2d-d0e5-471d-93c4-b89c40cea58b' and greeting = '' and char_length(intro) between 80 and 2000;
update public.public_personas set greeting = 'Hiya, I''m Priya. Right – where does it hurt?' where id = '24174745-169c-4196-99ce-a216eabe7160' and greeting = '' and char_length(intro) between 80 and 2000;
update public.public_personas set greeting = 'Hey! Just off a call with Chicago. Got a minute?' where id = 'adb4c800-ae75-42e9-8b99-c31218f422df' and greeting = '' and char_length(intro) between 80 and 2000;
update public.public_personas set greeting = 'Hi, take a seat! So, tell me what you actually did there.' where id = '59cf2daa-aad7-429d-bbff-84911b7b02e8' and greeting = '' and char_length(intro) between 80 and 2000;
update public.public_personas set greeting = 'Hi! Are you a parent here too? I''m Yuki.' where id = 'a9191e6b-78f5-4590-a57b-f198bf6b8cf1' and greeting = '' and char_length(intro) between 80 and 2000;
update public.public_personas set greeting = 'Hey! Been anywhere good lately? I''m always planning the next trip.' where id = '9080bd04-8b8d-4613-8692-d3b9bc31bc1d' and greeting = '' and char_length(intro) between 80 and 2000;
update public.public_personas set greeting = 'Hi! Just finished editing some photos – what are you up to?' where id = '217309f8-3723-4349-a1c5-4fb056ff5410' and greeting = '' and char_length(intro) between 80 and 2000;
update public.public_personas set greeting = 'Hi! I''m holly, up in Donegal – lovely weather for staying in!' where id = '1905c783-fa30-4fee-896e-14e22669e491' and greeting = '' and char_length(intro) between 80 and 2000;
update public.public_personas set greeting = 'Hi! I''ve just started oil painting again – do you paint?' where id = '7976a0db-456e-4017-b611-f4d333e4c08f' and greeting = '' and char_length(intro) between 80 and 2000;
update public.public_personas set greeting = 'Hey, Mark from Busan! Travelling anywhere soon?' where id = 'fd5bfc96-5105-4607-8c5e-8d489530139c' and greeting = '' and char_length(intro) between 80 and 2000;
update public.public_personas set greeting = 'Hi! Two hours on the bus home, so Stray Kids is on.' where id = 'dc32be7d-f4c3-4e69-a364-f3f5727cd443' and greeting = '' and char_length(intro) between 80 and 2000;
update public.public_personas set greeting = 'Hi from Langley! How''s your day going?' where id = 'd8c10ed0-11fd-4c9c-9d2e-00d92e3892ac' and greeting = '' and char_length(intro) between 80 and 2000;
update public.public_personas set greeting = 'Hi, I''m Jin from Phnom Penh! Long day at the NGO today.' where id = '134c40d1-60ba-456a-a6ec-9e618359dbc1' and greeting = '' and char_length(intro) between 80 and 2000;
update public.public_personas set greeting = 'Hi, I''m Moeka! Do you know Shiina Ringo?' where id = '2ec6ba8f-bf71-44e7-ae7e-a01e5484b910' and greeting = '' and char_length(intro) between 80 and 2000;
update public.public_personas set greeting = '안녕하세요, 어디가 어떻게 불편해서 오셨어요?' where id = '46d4523c-ba9a-4bdf-a41d-cdcf2b68ed1d' and greeting = '' and char_length(intro) between 80 and 2000;
update public.public_personas set greeting = '오셨어요? 잠깐 앉으세요, 아이 얘기 좀 나눠요.' where id = '76574ba8-863a-4767-a8f4-667a03c6ed9a' and greeting = '' and char_length(intro) between 80 and 2000;
update public.public_personas set greeting = '어서 오세요! 계약서 보러 오셨죠? 편하게 물어보세요.' where id = '64fddf9c-6e87-4379-8341-62f862aed81f' and greeting = '' and char_length(intro) between 80 and 2000;
update public.public_personas set greeting = '어서 와요. 먼 길 오느라 고생했죠? 밥은 먹었어요?' where id = 'd17a80db-13e6-4549-a2cc-e71277f99759' and greeting = '' and char_length(intro) between 80 and 2000;
update public.public_personas set greeting = '어머, 안녕하세요. 엘리베이터에서 또 만나네요.' where id = '70d84e37-21b0-410e-97f4-d96b5d5246a4' and greeting = '' and char_length(intro) between 80 and 2000;
update public.public_personas set greeting = '어, 왔어? 이번 주 일정 얘기 좀 할 수 있어?' where id = '7baf9b25-adf0-461c-a73a-c5605eded769' and greeting = '' and char_length(intro) between 80 and 2000;
update public.public_personas set greeting = '안녕하세요! 저 타오예요. 혹시 시간 괜찮아요?' where id = 'f85423da-02bd-44ce-a672-003dd17daccb' and greeting = '' and char_length(intro) between 80 and 2000;
update public.public_personas set greeting = '어, 오셨네요! 오늘 루트 좋던데요, 같이 해볼래요?' where id = '4163be7e-2a25-495a-8ce2-30a488e6c6dc' and greeting = '' and char_length(intro) between 80 and 2000;
