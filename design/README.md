# Design assets

## Re:Box design handoff

`design/re-box/` contains the extracted Re:Box macOS design handoff
(HTML/CSS/JSX prototype). This is the source of truth for the current
UI iteration.

Primary design file: `re-box/project/Re:Box macOS.html`

Key references:
- `re-box/project/app/colors_and_type.css` — color tokens, typography, spacing, radii
- `re-box/project/app/app.css` — layout and component measurements
- `re-box/project/app/*.jsx` — component-level reference (Sidebar, Toolbar, ThreadList, ReadingPane, AIBrief, ActionSheet, Composer)
- `re-box/project/app/data.js` — fixture data used by the prototype

Out of scope for this iteration:
- `Re:Box ReadingPane v2*.html` + `cards-v2.*` — alternative reading-pane explorations
- `Re:Box Wireframes.html` + section1–section4 — wireframe explorations
