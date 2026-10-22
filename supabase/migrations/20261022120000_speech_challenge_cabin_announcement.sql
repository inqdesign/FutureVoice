-- The fourth speech challenge: the cabin announcement before take-off.
--
-- Founder's idea (2026-10-22): "Ladies and gentlemen, this aircraft…" —
-- everyone has heard it a hundred times, and reading it out like a crew
-- member is fun. It is also the one register every language keeps formal on
-- purpose, so each row is written in that language's own announcement
-- style, not translated: Korean 합니다체 (손님 여러분, …십시오), Japanese
-- 機内アナウンスの敬語 (皆さま、…いたします、…でございます), German
-- "Meine sehr geehrten Damen und Herren" with Sie, Spanish ustedes.
--
-- The airline is the app's own name (nawana Air), never a real carrier,
-- and there is no flight number: a number is read differently by every
-- crew ("seven oh two", 칠공이) and the scorer would mark the reading wrong.
-- Same shape as `20261018120000`: one row per target language.

insert into public.speech_challenges (id, language, title, genre, body, target_seconds)
values
  ('5beec000-0000-4000-8000-000000000010', 'en', 'Ladies and gentlemen, welcome aboard', 'briefing',
   'Good evening, ladies and gentlemen, and welcome aboard this nawana Air flight to London.

Boarding is now complete, and the cabin door has been closed. Please make sure your seatbelt is fastened, your seat back is upright, and your tray table is stowed.

Please switch all mobile phones and other electronic devices to flight mode. Larger devices, such as laptops, must be stowed in the overhead bins or under the seat in front of you for take-off.

In a few moments, our cabin crew will show you the safety features of this aircraft. Please take a moment to find your nearest exit. It may be behind you.

Our flight time to London today is about eleven hours. Shortly after take-off, we will be serving dinner and drinks.

This is a non-smoking flight, and smoking is not permitted anywhere on board, including in the lavatories.

On behalf of the captain and the whole crew, thank you for flying with us. Sit back, relax, and enjoy the flight.', 60),

  ('5beec000-0000-4000-8000-000000000011', 'ko', '손님 여러분, 안녕하십니까', 'briefing',
   '손님 여러분, 안녕하십니까. 오늘도 나와나 항공을 이용해 주셔서 감사합니다. 이 비행기는 인천을 출발하여 베를린까지 가는 나와나 항공입니다.

지금 손님 여러분의 탑승이 모두 끝나, 출입문을 닫았습니다. 좌석벨트를 매 주시고, 등받이와 테이블을 제자리로 해 주시기 바랍니다.

휴대전화 등 전자기기는 비행기 모드로 바꿔 주십시오. 노트북처럼 큰 전자기기는 이륙하는 동안 머리 위 선반이나 앞 좌석 아래에 넣어 주시기 바랍니다.

잠시 후 승무원이 비상시 안전에 관해 안내해 드리겠습니다. 가장 가까운 비상구가 어디에 있는지 꼭 확인해 주십시오. 비상구는 뒤쪽에 있을 수도 있습니다.

목적지인 베를린까지는 이륙 후 약 열네 시간이 걸릴 예정입니다. 이륙하고 잠시 후, 저녁 식사와 음료를 준비해 드리겠습니다.

이 비행기는 전 구간 금연입니다. 화장실을 포함한 모든 곳에서 담배를 피우실 수 없습니다.

기장과 승무원 모두, 손님 여러분을 편안하게 모시겠습니다. 즐거운 여행 되십시오. 감사합니다.', 60),

  ('5beec000-0000-4000-8000-000000000012', 'ja', '皆さま、本日はご搭乗ありがとうございます', 'briefing',
   '皆さま、こんばんは。本日もナワナ航空をご利用いただきまして、誠にありがとうございます。この便は、羽田発、ロンドン行きでございます。

ただいま、皆さまのご搭乗が完了し、ドアを閉めました。シートベルトをしっかりとお締めください。座席の背もたれ、テーブルを元の位置にお戻しください。

携帯電話などの電子機器は、機内モードに設定してください。パソコンなどの大きな電子機器は、離陸の間、頭上の棚か、前の座席の下にお入れください。

まもなく、客室乗務員が非常用設備についてご案内いたします。お近くの非常口の位置をご確認ください。非常口は後ろにある場合もございます。

ロンドンまでの飛行時間は、離陸後、およそ十四時間を予定しております。離陸後しばらくいたしまして、お食事とお飲み物をご用意いたします。

機内はすべて禁煙となっております。化粧室を含め、機内でのおたばこはご遠慮ください。

機長はじめ乗務員一同、皆さまに快適な空の旅をお楽しみいただけますよう、心を込めてお手伝いいたします。どうぞごゆっくりおくつろぎください。', 60),

  ('5beec000-0000-4000-8000-000000000013', 'de', 'Meine Damen und Herren, willkommen an Bord', 'briefing',
   'Meine sehr geehrten Damen und Herren, guten Abend und herzlich willkommen an Bord dieses nawana-Air-Fluges nach Seoul.

Das Boarding ist abgeschlossen, und die Türen sind geschlossen. Bitte schnallen Sie sich an, stellen Sie Ihre Rückenlehne senkrecht und klappen Sie Ihren Tisch hoch.

Bitte schalten Sie Ihr Handy und alle anderen elektronischen Geräte in den Flugmodus. Größere Geräte wie Laptops verstauen Sie bitte für den Start in den Gepäckfächern oder unter dem Sitz vor Ihnen.

Gleich zeigt Ihnen unsere Kabinenbesatzung die Sicherheitseinrichtungen an Bord. Bitte merken Sie sich den nächsten Notausgang. Er kann sich auch hinter Ihnen befinden.

Unsere Flugzeit nach Seoul beträgt heute etwa elf Stunden. Kurz nach dem Start servieren wir Ihnen das Abendessen und Getränke.

Dies ist ein Nichtraucherflug. Das Rauchen ist an Bord überall verboten, auch in den Toiletten.

Im Namen unseres Kapitäns und der gesamten Crew danken wir Ihnen, dass Sie mit uns fliegen. Lehnen Sie sich zurück und genießen Sie den Flug.', 60),

  ('5beec000-0000-4000-8000-000000000014', 'es', 'Señoras y señores, bienvenidos a bordo', 'briefing',
   'Señoras y señores, buenas noches y bienvenidos a bordo de este vuelo de nawana Air con destino a Madrid.

El embarque ha terminado y la puerta del avión ya está cerrada. Les rogamos que se abrochen el cinturón de seguridad, pongan el respaldo de su asiento en posición vertical y plieguen la mesita.

Por favor, pongan sus teléfonos y demás dispositivos electrónicos en modo avión. Los dispositivos más grandes, como los portátiles, deben guardarse durante el despegue en los compartimentos superiores o debajo del asiento de delante.

En unos momentos, nuestra tripulación les mostrará las medidas de seguridad de este avión. Les pedimos que localicen la salida de emergencia más cercana. Puede estar detrás de ustedes.

La duración de nuestro vuelo hasta Madrid será de unas doce horas. Poco después del despegue, les serviremos la cena y bebidas.

Les recordamos que está prohibido fumar en todo el avión, también en los baños.

En nombre del comandante y de toda la tripulación, les agradecemos que vuelen con nosotros. Relájense y disfruten del vuelo.', 60)
on conflict (id) do nothing;
