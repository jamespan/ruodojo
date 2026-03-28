# Ruodojo - Jekyll Blog

## Key Facts

- **CSS**: Must edit `css/style.css` directly. Do NOT rely on `_sass/` changes — the static `style.css` takes precedence in the build.
- **SCSS source**: `_sass/` exists but changes there may not reflect in production. Only edit for reference.
- **Build**: GitHub Pages with Jekyll. No custom GitHub Actions workflow.

## Project Structure

- `_posts/` — Blog posts (Chinese: `YYYY-MM-DD-slug.md`, English: `YYYY-MM-DD-slug-en.md`)
- `_layouts/` — HTML templates
- `_data/settings.yml` — Site settings (colors, fonts, etc.)
- `css/style.css` — Production CSS (edit this file directly)
- `css/style.scss` — SCSS source (may not override style.css in build)
- `_sass/` — SCSS partials

## Design Tokens (from compiled CSS)

- `$text-dark-color`: `#2A2F36`
- `$text-medium-color`: `#6C7A89`
- `$text-light-color`: `#ABB7B7`
- `$accent-color`: `#A2DED0`
- `$background-color`: `#fff`
- `$border-color`: `#ddd`
