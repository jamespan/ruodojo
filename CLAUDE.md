# Ruodojo - Jekyll Blog

## Key Facts

- **CSS**: Edit `_sass/` SCSS files. Jekyll compiles `css/style.scss` → `css/style.css`. Do NOT create a static `css/style.css` — it will shadow the SCSS output.
- **Build**: GitHub Pages with Jekyll + custom GitHub Actions workflow (`.github/workflows/deploy.yml`).
- **Clean Markdown**: The workflow generates clean `.md` files (no frontmatter, `# Title` header) at `/md/<slug>.md`. Slug is extracted from `_posts/` filename: `YYYY-MM-DD-<slug>.md` → `/md/<slug>.md`.

## Project Structure

- `_posts/` — Blog posts (Chinese: `YYYY-MM-DD-slug.md`, English: `YYYY-MM-DD-slug-en.md`)
- `_layouts/` — HTML templates
- `_data/settings.yml` — Site settings (colors, fonts, etc.)
- `css/style.scss` — Main SCSS entry point (imports `_sass/` partials)
- `_sass/` — SCSS partials (`_basic.scss`, `_includes/_content.scss`, etc.)

## SCSS Breakpoints

- `phonel`: 480px
- `tabletp`: 768px
- `tabletl`: 1024px
- `laptop`: 1220px
- `desktop`: 1600px

## Design Tokens

Defined in `_data/settings.yml`, referenced as Liquid variables in `css/style.scss`:

- `$text-dark-color`: `#2A2F36`
- `$text-medium-color`: `#6C7A89`
- `$text-light-color`: `#ABB7B7`
- `$accent-color`: `#A2DED0`
- `$background-color`: `#fff`
- `$border-color`: `#ddd`
