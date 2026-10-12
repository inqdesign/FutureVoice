-- Every curated Find-people persona gets its OWN Cartesia stock voice (2026-10-12).
--
-- Until now the 88 curated rows shared the four ElevenLabs presets, so a
-- landlord, a nurse and a recruiter all sounded like Paige or Mark. Each
-- person is cast by gender, age, background and manner (scripts/people-voice-casting.py,
-- samples heard by the founder). Cartesia ids are UUIDs, which is how the
-- servers route a voice to Cartesia (supabase/functions/_shared/cartesia.ts).
--
-- NOT YET APPLIED: the gateway's PRESET_VOICE_IDS and elevenlabs-tts allowlist
-- must accept these ids first, or every call with these people is refused.

update public.public_personas p set voice_preset_id = c.voice_id
from (values
  ('df49b150-0032-4826-9d26-01185e3f84e9'::uuid, 'db229dfe-f5de-4be4-91fd-7b077c158578'),  -- de Andrej → Andreas
  ('1b11effc-56a3-4630-9881-62ffe83b05ea'::uuid, 'de07efe3-b309-418b-bdca-42827223efd2'),  -- de Ayşe → Rena
  ('911d3d33-da52-40bd-8b52-2e1df5f60674'::uuid, '6d4b1416-8d54-4d94-a788-8a802c086544'),  -- de Britta → Sabine
  ('678f5980-9762-4dff-a87c-3b697f31203b'::uuid, '6d4b1416-8d54-4d94-a788-8a802c086544'),  -- de Britta → Sabine
  ('51bb9655-876d-40ff-a9c7-08362d2703f5'::uuid, '24c61c42-b538-468e-a9ad-16c7a032c9cb'),  -- de Bruno → Klaus
  ('7a9f4e27-8e39-41e9-99ee-017323005354'::uuid, '3f4ade23-6eb4-4279-ab05-6a144947c4d5'),  -- de Emine → Karin
  ('4f75d85d-0348-40ff-955c-9d2cdfe4a20b'::uuid, '3f4ade23-6eb4-4279-ab05-6a144947c4d5'),  -- de Emine → Karin
  ('e845903f-2e1d-443e-8ae0-5b8b38b6d996'::uuid, '2578354e-4b18-4d28-832c-5943344b7085'),  -- de Frau Weber → Klara
  ('4be3d302-5f85-44a2-8840-ca61ae891ff7'::uuid, '2578354e-4b18-4d28-832c-5943344b7085'),  -- de Frau Weber → Klara
  ('4c9be2d8-1d58-4785-914e-d71e2c447a8d'::uuid, '0b66a153-548f-4f2c-b734-09a13b0bd163'),  -- de Hanne → Lorelei
  ('d95001e0-0bae-4dbe-9498-00bbced4ea26'::uuid, 'd42fc8d7-efdd-44df-bb2e-a6e093601917'),  -- de Herr Klein → Oskar
  ('c7b0c884-35cc-4ff5-ad7d-e645c11ef124'::uuid, 'd42fc8d7-efdd-44df-bb2e-a6e093601917'),  -- de Herr Klein → Oskar
  ('87bcff24-91d1-4703-9a26-ed4837f16daf'::uuid, 'afa425cf-5489-4a09-8a3f-d3cb1f82150d'),  -- de Jonas → Nico
  ('ff0ede56-e025-49f4-b8fa-be8a233b81fe'::uuid, 'dff81230-ff75-49a4-af44-f6b2f43500d8'),  -- de Jonas → Jonas
  ('cdbe1d62-e127-4685-9624-d64ee8931441'::uuid, 'afa425cf-5489-4a09-8a3f-d3cb1f82150d'),  -- de Jonas → Nico
  ('8e5bfcd5-e30a-455f-8ae5-50e9b46a5a53'::uuid, '38aabb6a-f52b-4fb0-a3d1-988518f4dc06'),  -- de Katja → Alina
  ('b8a74bd9-b1b8-46f3-9f10-5ecde095666a'::uuid, '4ab1ff51-476d-42bb-8019-4d315f7c0c05'),  -- de Lena → Lena
  ('36b5100e-bb77-4124-af76-8f05c622c1e7'::uuid, '384b625b-da5d-49e8-a76d-a2855d4f31eb'),  -- de Marek → Thomas
  ('f72995e3-c769-4053-aa7b-c086789eea05'::uuid, '384b625b-da5d-49e8-a76d-a2855d4f31eb'),  -- de Marek → Thomas
  ('3a973668-5520-46d5-9a58-64a95f2c387f'::uuid, '3264ada2-4a79-4666-badc-49e2267be692'),  -- de Mehmet → Christian
  ('eab29ae6-5c92-4eec-ab92-5a0a62bf8a5e'::uuid, '758a5cff-af0b-4bdf-84bd-4c1b5525c249'),  -- de Nguyen → Leander
  ('b1d690d4-2fbc-4edf-90de-7d860776ae1b'::uuid, '758a5cff-af0b-4bdf-84bd-4c1b5525c249'),  -- de Nguyen → Leander
  ('d9dd7f00-ddab-406a-a648-1477bd02d195'::uuid, 'adc919b3-6ebf-47fd-8a46-27c5169d6d94'),  -- de Resi → Leni
  ('20388726-1f2a-4a4a-9b86-7ba468572b7f'::uuid, 'ac197a78-cec7-4c50-93e5-93bdc1910b11'),  -- de Sofia → Jennifer
  ('fd782246-0351-4997-ba22-438176933fb5'::uuid, 'ac197a78-cec7-4c50-93e5-93bdc1910b11'),  -- de Sofia → Jennifer
  ('a2e29556-a865-428a-9430-fb089ca3bd96'::uuid, '43a317e9-f1b9-45bf-bbdb-1d4a52e46f0d'),  -- de Svenja → Emi
  ('bdeec9b8-462e-4aa1-a5d9-968c848ffa42'::uuid, 'e00dd3df-19e7-4cd4-827a-7ff6687b6954'),  -- de Timo → Lukas
  ('dee6b173-375e-43c3-ad5b-17ae1052e639'::uuid, 'f1cdfb4a-bf7d-4e83-916e-8f0802278315'),  -- en Amir → Walid
  ('7f54389d-d19a-4c27-bae9-8ed473f00cf2'::uuid, 'f1cdfb4a-bf7d-4e83-916e-8f0802278315'),  -- en Amir → Walid
  ('7bb552ea-bd91-4b3a-a736-ab1372a8950a'::uuid, '273f9ef7-9fc2-4def-88bb-ab108c6249ca'),  -- en Aoife → Julia
  ('e289aa95-b4d1-4da6-91fa-a2436f5ccb60'::uuid, '8d8ce8c9-44a4-46c4-b10f-9a927b99a853'),  -- en Bea → Connie
  ('96927969-e969-4063-abb7-1184837c657b'::uuid, '537a82ae-4926-4bfb-9aec-aff0b80a12a5'),  -- en Dae-ho → Minho
  ('fb8a5e68-5bb6-4f03-8daf-9ae0a02778cb'::uuid, '8499aae3-022c-4d55-8283-0c2e8adbefb4'),  -- en Diego → Ricardo
  ('9cc7abbf-04fa-405a-ad54-ce89646ea849'::uuid, '8499aae3-022c-4d55-8283-0c2e8adbefb4'),  -- en Diego → Ricardo
  ('8a435c8b-677b-4d4b-8797-1ddb8d27b42e'::uuid, '1fcd23d0-bf12-4896-8f60-4f21ef5c9b98'),  -- en Frank → Austin
  ('e4c8d4cc-8f1e-49e2-8c3f-78bec41a4cce'::uuid, '1fcd23d0-bf12-4896-8f60-4f21ef5c9b98'),  -- en Frank → Austin
  ('cc952756-5547-41a3-9624-4739d20fbec5'::uuid, '6b92f628-be90-497c-8f4c-3b035002df71'),  -- en Hiroshi → Kenji
  ('47a9b738-5266-4ce1-b16b-e41d947473ea'::uuid, '24894159-1d4e-4b7c-80ca-4ae37dce9400'),  -- en Ingrid → Tamsin
  ('28fd5700-28d0-4a5c-86e8-c91c9627be54'::uuid, '56c7989e-7a5f-4d12-838f-e0f910e7356e'),  -- en Kwame → Tristan
  ('5633635c-2a0e-4104-8c33-5f4864f563cb'::uuid, '741a0606-3f3a-430e-a928-aa81be7a5aef'),  -- en Lucia → Gabriela
  ('8190e85e-7871-484d-a126-68f2afc58e43'::uuid, 'c99d36f3-5ffd-4253-803a-535c1bc9c306'),  -- en Marcus → Griffin
  ('f3271080-6101-4df4-9f06-1a38048d1232'::uuid, '5abd2130-146a-41b1-bcdb-974ea8e19f56'),  -- en Marta → Jo
  ('8d74edbd-8467-4b51-99e3-ef517594c783'::uuid, '5abd2130-146a-41b1-bcdb-974ea8e19f56'),  -- en Marta → Jo
  ('7026fb7f-a87f-46fb-bbb3-c13f493341d7'::uuid, '391f4c0a-f1a8-4c21-9aa2-7a07f0a4b0dc'),  -- en Maya → Bronte
  ('f560fe6e-9962-4397-ab64-07fad77c789a'::uuid, 'ec1e269e-9ca0-402f-8a18-58e0e022355a'),  -- en Michelle → Ariana
  ('d3c65d2d-d0e5-471d-93c4-b89c40cea58b'::uuid, 'ec1e269e-9ca0-402f-8a18-58e0e022355a'),  -- en Michelle → Ariana
  ('3064334d-8208-48f2-92f3-a18f0a6acd34'::uuid, 'c8ad77a8-42b9-4f69-8ed3-a2801c3e223d'),  -- en Nadia → Daniela
  ('8bbf2afc-f2be-4e7f-afb8-293afb5138bb'::uuid, '3d5ce2fb-e56c-42f0-9ed9-4662484063b4'),  -- en Owen → Toby
  ('3c04cde8-cbfc-4d14-bd6b-3405adb7e787'::uuid, '07bc462a-c644-49f1-baf7-82d5599131be'),  -- en Priya → Sindhu
  ('31a53dc3-26ef-4dda-ba08-f1acaf3bee69'::uuid, '7c6219d2-e8d2-462c-89d8-7ecba7c75d65'),  -- en Priya → Divya
  ('24174745-169c-4196-99ce-a216eabe7160'::uuid, '07bc462a-c644-49f1-baf7-82d5599131be'),  -- en Priya → Sindhu
  ('d36a2f87-c06b-4807-b379-b9b4879b5468'::uuid, '8499aae3-022c-4d55-8283-0c2e8adbefb4'),  -- en Rafael → Ricardo
  ('78e4f0ce-cc4d-4621-8569-5055c4be770a'::uuid, '393dd459-f8d8-4c3e-a86b-ec43a1113d0b'),  -- en Ravi → Rahul
  ('adb4c800-ae75-42e9-8b99-c31218f422df'::uuid, '393dd459-f8d8-4c3e-a86b-ec43a1113d0b'),  -- en Ravi → Rahul
  ('b3d83f31-3b53-47fd-aa43-06b956dfd162'::uuid, '6303e5fb-a0a7-48f9-bb1a-dd42c216dc5d'),  -- en Samir → Sagar
  ('5bc40cfe-eb60-4d76-89a5-63f72129440a'::uuid, 'e5d4c33a-d8f6-46e8-a10f-b5afecc35648'),  -- en Sarah → Evie
  ('59cf2daa-aad7-429d-bbff-84911b7b02e8'::uuid, 'e5d4c33a-d8f6-46e8-a10f-b5afecc35648'),  -- en Sarah → Evie
  ('4dbd3ba7-e7b5-49e5-a4e8-7de6fd677415'::uuid, 'ae823354-f9be-4aef-8543-f569644136b4'),  -- en Sofia → Mariana
  ('1e9cc3b4-2460-4a2e-81eb-836765e2ef3e'::uuid, '1fc31370-81b1-4588-9c1a-f93793c6e01d'),  -- en Tomás → Carlo
  ('a9191e6b-78f5-4590-a57b-f198bf6b8cf1'::uuid, '63d6f469-8c2c-489d-b53f-d36f0bbdcd4b'),  -- en Yuki → Ayako
  ('9ce833e4-f3d5-4ea1-8435-3c9f3d703f6b'::uuid, '63d6f469-8c2c-489d-b53f-d36f0bbdcd4b'),  -- en Yuki → Ayako
  ('46d4523c-ba9a-4bdf-a41d-cdcf2b68ed1d'::uuid, '90dba946-774b-40ed-98d9-ac3835117827'),  -- ko 간호사 수진 → Hyerin
  ('6afea5c2-0832-4933-85b4-d76f25763c38'::uuid, '90dba946-774b-40ed-98d9-ac3835117827'),  -- ko 간호사 수진 → Hyerin
  ('26305ea5-4f8f-48ab-9981-ded67b441a42'::uuid, 'cac92886-4b7c-4bc1-a524-e0f79c0381be'),  -- ko 미선 → Yuna
  ('a4e578e6-6650-4f07-8f9b-3995f6807d9c'::uuid, 'd6d687b4-5d1e-4eb7-8c5a-1eb608532772'),  -- ko 민규 → Junho
  ('f2589789-cc31-4a9e-a019-ca070e2b204e'::uuid, 'ce9ca2b6-2bed-4452-99bb-052e1ec0b534'),  -- ko 민정 선생님 → Seoyun
  ('76574ba8-863a-4767-a8f4-667a03c6ed9a'::uuid, 'ce9ca2b6-2bed-4452-99bb-052e1ec0b534'),  -- ko 민정 선생님 → Seoyun
  ('ef5ecdfb-7aa8-49a3-ab58-7c20a196d271'::uuid, '89f4372f-1f73-4b85-8e1e-5d24ed8bc826'),  -- ko 박 사장님 → Jaewon
  ('64fddf9c-6e87-4379-8341-62f862aed81f'::uuid, '89f4372f-1f73-4b85-8e1e-5d24ed8bc826'),  -- ko 박 사장님 → Jaewon
  ('19e3d746-212a-48d5-9a9b-5f34bd68342b'::uuid, '7706804e-ea85-443a-968a-b9bf363bdde8'),  -- ko 보라 → Minji
  ('44a7d73d-6518-40c2-b7a5-92e3a0391130'::uuid, '4dd4630e-19e0-4243-bca0-676ff85119b7'),  -- ko 순자 → Haeun
  ('6b8a9bfa-dd08-4469-a37d-8973d09d30b9'::uuid, 'a0fc16d3-01af-482b-910f-ed063c3d79d3'),  -- ko 어머님 → Subin
  ('d17a80db-13e6-4549-a2cc-e71277f99759'::uuid, 'a0fc16d3-01af-482b-910f-ed063c3d79d3'),  -- ko 어머님 → Subin
  ('70d84e37-21b0-410e-97f4-d96b5d5246a4'::uuid, '304fdbd8-65e6-40d6-ab78-f9d18b9efdf9'),  -- ko 영숙 아주머니 → Jihyun
  ('7cac1215-ce4d-47bf-a1d9-081298894da2'::uuid, '304fdbd8-65e6-40d6-ab78-f9d18b9efdf9'),  -- ko 영숙 아주머니 → Jihyun
  ('1e2eb4d3-a9a3-4b08-aa1d-135569726a22'::uuid, '1a602be4-3b57-4bef-a270-dfa5efed0541'),  -- ko 은영 → Yeji
  ('8da9035b-bb45-4b17-beeb-23cae97c13a0'::uuid, 'e1717dc3-b87b-4720-aa7f-b6db290e0609'),  -- ko 재원 → Taehyun
  ('bded3c14-37cd-4fd2-bb9e-c2d79fc00301'::uuid, '89f4372f-1f73-4b85-8e1e-5d24ed8bc826'),  -- ko 정훈 → Jaewon
  ('dfeaa034-ea41-4081-9957-3deb9f9f4b74'::uuid, 'e1717dc3-b87b-4720-aa7f-b6db290e0609'),  -- ko 종석 → Taehyun
  ('f48dec1d-8c25-452b-88e7-069cb167fa9b'::uuid, 'cd6c48a9-774b-4397-98b4-9948c0a790f0'),  -- ko 지현 선배 → Soojin
  ('7baf9b25-adf0-461c-a73a-c5605eded769'::uuid, 'cd6c48a9-774b-4397-98b4-9948c0a790f0'),  -- ko 지현 선배 → Soojin
  ('10a841bc-00ec-4430-9ecf-dd118f6a8b2e'::uuid, 'f7755efb-1848-4321-aa22-5e5be5d32486'),  -- ko 타오 → Ryeowook
  ('f85423da-02bd-44ce-a672-003dd17daccb'::uuid, 'f7755efb-1848-4321-aa22-5e5be5d32486'),  -- ko 타오 → Ryeowook
  ('515085fa-e3e9-4aa8-b7af-f1355e4f95f7'::uuid, 'f7755efb-1848-4321-aa22-5e5be5d32486'),  -- ko 태오 → Ryeowook
  ('13d59713-3dc3-4b69-9fe4-3e3121244485'::uuid, '69c18e1d-fab0-4747-b9da-58617cd8b9e4'),  -- ko 하늘 → Soyeon
  ('db93818a-1f13-4d04-a5cd-f63dce77f0bf'::uuid, '537a82ae-4926-4bfb-9aec-aff0b80a12a5'),  -- ko 현우 → Minho
  ('4163be7e-2a25-495a-8ce2-30a488e6c6dc'::uuid, '537a82ae-4926-4bfb-9aec-aff0b80a12a5'),  -- ko 현우 → Minho
  ('937b6bd3-4f11-44d1-9500-beb82020ae0b'::uuid, 'd6d687b4-5d1e-4eb7-8c5a-1eb608532772')  -- ko 현우 → Junho
) as c(id, voice_id)
where p.id = c.id and p.owner_user_id is null;
