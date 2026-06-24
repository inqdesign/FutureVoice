# Future Voice — marketing landing page

Single static page, no build step. Everything (CSS/JS) is inlined in `index.html`.

## Preview

```bash
open web/index.html
```

## Deploy

Any static host works. Point the project root at `web/`:

- **Vercel**: `vercel --cwd web` (or set Root Directory to `web` in the dashboard, framework preset "Other").
- **Cloudflare Pages**: build command none, output directory `web`.

## Before launch

- [ ] Replace `TESTFLIGHT_URL` in the inline `<script>` at the bottom of `index.html` with the public TestFlight invite link. All CTAs (`[data-testflight]`) pick it up automatically.
- [ ] Add an `og:image` (1200x630) and reference it in the meta tags.
- [ ] Privacy policy page + footer link (required before App Store launch).

## Conventions

- Fonts: Fraunces (display / "Future you" voice lines, italic) + Schibsted Grotesk (body), via Google Fonts.
- Colors are CSS variables in `:root` — paper `#F7F1E6`, ink `#221D17`, signal red `#E0472B`, dark `#1C1712`.
- No emojis anywhere; icons are inline SVG strokes.
- Company name in legal/footer text is always "Dear RoRo".
