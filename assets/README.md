# assets

## `icon.png` / `icon.svg` — the marketplace icon

The OpenAI logomark, used to identify the software this template deploys.

- **Source:** Railway's own devicons service, <https://devicons.railway.com/i/openai.svg>
  (`devicons.railway.app/i/openai.svg` 301s to it). Not redrawn, not generated —
  the path data is verbatim from that file.
- **The only change** is the monochrome fill, `#000000` → `#FFFFFF`. The mark is a
  single-path monochrome logo meant to be recoloured; black would be invisible on
  Railway's dark template cards.
- `icon.png` is that white mark centred on a solid near-black rounded tile at
  1024×1024, so it stays legible on light backgrounds too. 1024×1024 matches the
  convention used by the other templates in this workspace.
- Regenerate with `scripts/make-icon.py` if the upstream mark ever changes.

> There is **no Codex-specific devicon.** `devicons.railway.app/i/codex.svg` silently
> serves *Gitpod's* logo — the service falls back rather than 404ing, so don't trust it.

> The OpenAI name and logo are OpenAI's trademarks. They are used here only to
> identify the upstream software being deployed. This template is not affiliated with
> or endorsed by OpenAI.

## Optional extras

- `card.png` *(optional)* — a wider marketplace card. Note that Railway's `--image`
  renders as a small **icon**, not a banner, so a wide screenshot reads poorly there.
  Upstream's official splash (`.github/codex-cli-splash.png` in `openai/codex`,
  1898×1190) is the right asset if a hero image is ever wanted in `TEMPLATE.md`.

Publish with a **commit-pinned** raw GitHub URL (`raw.../<sha>/assets/icon.png`),
never `/main/` — branch refs lag by minutes on the raw layer.
