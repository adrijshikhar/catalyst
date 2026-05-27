### Axes

| Axis | What it measures |
|------|------------------|
| `semantic_html` | Are elements semantically correct? `<button>` for buttons, `<a>` for navigation, headings in order, landmarks present, lists for lists? No `<div onclick>` masquerading as a control. |
| `aria` | Are ARIA attributes correct and minimal? Required roles present, redundant ones absent. `aria-label` on icon-only controls. Live regions for dynamic updates. |
| `keyboard_nav` | Tab order is logical. Focus is visible. Focus traps in modals work both ways (open + escape). Skip-links for repetitive nav. No keyboard dead-ends. |
| `contrast` | Text meets WCAG AA contrast (4.5:1 body, 3:1 large). Non-text UI (focus rings, icons) meets 3:1. Color is not the sole information channel. |

### Score anchors (each axis 1-5)

- **5 — Exemplary.** WCAG 2.2 AA across the board, with documented AAA aspirations where possible.
- **4 — Solid.** WCAG 2.2 AA met. Minor improvements possible.
- **3 — Acceptable.** Specific failures to fix before ship.
- **2 — Needs work.** Multiple violations; will fail audit.
- **1 — Reject.** Critical barrier (no keyboard access, no focus, no labels).

### Critique guidance

Score ≤3 must cite the element / component + the WCAG success criterion failed (e.g., 1.4.3 contrast) + the concrete fix. If `axe-core` output is provided, reference the rule ID.
