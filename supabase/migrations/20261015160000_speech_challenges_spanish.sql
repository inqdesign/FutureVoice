-- Spanish becomes a selectable target language (2026-10-15), so it gets the
-- two challenges every other target has, each WRITTEN in Spanish rather than
-- translated (same rule as `20261010150000` and `20261015120000`).
--
-- Neutral Spanish for Spain and Latin America alike: tú, never vosotros, and
-- no region-locked words.
--
--   * ...009 is the bundled sample (`SpeechLibrary.builtInId("es")`), so its
--     text must stay byte-identical to `builtInBodies["es"]` in the app.
--   * ...00a is the ageing study, the same claims as the other languages'
--     copies: "más probabilidades", not "el doble" (the odds ratio is 2.11,
--     the relative risk 1.43).

insert into public.speech_challenges (id, language, title, genre, body, target_seconds)
values
  ('5beec000-0000-4000-8000-000000000009', 'es', '¿Por qué practicar en voz alta?', 'explainer',
   '¿Te ha pasado alguna vez? Tienes la frase perfecta en la cabeza, y en cuanto la dices en voz alta, se viene abajo.

Hablar es una habilidad, no solo un conocimiento. Puedes saber las palabras y la gramática, pero si tu boca nunca ha armado esa frase, te va a fallar justo cuando más la necesitas. Por eso hay que practicar en voz alta.

Decir las cosas en voz alta también ayuda a recordarlas. Hay estudios que indican que recordamos mejor lo que hemos dicho que lo que solo hemos leído.

Y si te grabas, notas cosas que de otra forma nunca descubrirías: lo rápido que hablas de verdad, cuántas veces dices «eh» o «mmm», y si la voz se te apaga al final de las frases.

Las presentaciones, las entrevistas, incluso una primera conversación con alguien nuevo: todo se vuelve más fácil con práctica. ¿Y el minuto que acabas de pasar leyendo esto en voz alta? Esa fue tu primera repetición.', 60)
on conflict (id) do nothing;

insert into public.speech_challenges (id, language, title, genre, body, sources, target_seconds)
values
  ('5beec000-0000-4000-8000-00000000000a', 'es', '¿Los idiomas te mantienen joven?', 'explainer',
   '¿Has oído alguna vez que aprender un idioma puede frenar el envejecimiento? Suena casi demasiado bueno para ser verdad, así que veamos qué dice realmente la investigación.

En 2025, la revista Nature Aging publicó un estudio muy grande. Los investigadores analizaron a más de ochenta y seis mil personas de entre cincuenta y uno y noventa años, en veintisiete países europeos. Las personas que hablaban un solo idioma tenían más probabilidades de envejecer más rápido de lo esperado. Y cuantos más idiomas hablaba alguien, menor era ese riesgo.

Pero hay un detalle importante. Un estudio así muestra una relación, no una causa. Quienes hablan varios idiomas pueden ser distintos también en otras cosas.

Entonces, ¿vale la pena empezar más tarde? Un estudio en Escocia encontró que las personas que aprendieron un segundo idioma ya de adultas también obtuvieron mejores resultados en la vejez de lo que predecían sus pruebas de la infancia. En cambio, en un experimento en Suecia, los adultos mayores que hicieron un curso de italiano de once semanas no mostraron ningún cambio en la memoria.

La respuesta sincera es que todavía no lo sabemos con seguridad. Pero un idioma nuevo te da una razón para hablar con gente nueva. Y eso no puede hacer daño.',
   '["https://doi.org/10.1038/s43587-025-01000-2", "https://doi.org/10.1002/ana.24158"]'::jsonb, 75)
on conflict (id) do nothing;
