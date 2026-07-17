---
name: drift-figma-handout-pack
description: Create a complete, read-only design handout from a Figma selection URL and save it locally with reference screenshots. Use when a user provides a Figma design link containing a node-id and asks for a design handoff, handout, implementation packet, property extraction, screenshots, or documented design specifications.
---

# Drift Figma Handout Pack

Inspect exactly one linked Figma selection and create a screenshot-backed handout without modifying Figma.

## Required input

Always ask the user for a Figma design selection URL before invoking this
skill. Require that URL to contain a `node-id` query parameter, and continue
only after the user supplies it and explicitly asks to prepare or start the
design handout. If the selection link is missing, pause and request it; do not
substitute product discussion, screenshots without a source selection, or a
whole-file Figma URL. Do not inspect unrelated frames, pages, or files.

## Output contract

Create this structure in the current project or workspace:

```text
design-handout/
└── <file-and-node-slug>/
    ├── handoud.md
    └── assets/
        ├── selection-overview.png
        ├── layer-structure.png
        ├── design-properties.png
        ├── prototype-properties.png
        └── detail-*.png
```

The filename is intentionally `handoud.md`; preserve that spelling.

Initialize the folder with:

```bash
python3 scripts/init_handout.py "<figma-selection-url>" --root "<workspace-root>"
```

Use `--name <slug>` only when the user supplies a handout name.

## Read-only rules

- Treat Figma as strictly read-only.
- Never create, edit, move, resize, rename, delete, comment on, publish, share, or change any node, property, component, variable, file, or setting.
- Allow only navigation, zooming, panning, selecting the target or its descendants, expanding existing panels, and reading properties.
- Do not enable accessibility or screen-reader settings merely to expose more data.
- Do not inspect sibling designs except where they are unavoidably visible in the layer list.
- Stop if the requested inspection would require a design mutation.

## Workflow

1. Validate the link and initialize the output folder.
2. Load and follow the Computer Use skill.
3. Prefer the Figma desktop app. Open or navigate to only the supplied file and node.
4. Confirm the selected node name and dimensions before collecting details.
5. Save an uncropped overview screenshot as `assets/selection-overview.png`.
6. Inspect and record:
   - Node name, ID, type, position, dimensions, rotation, visibility, opacity, clipping, radius, and blend mode.
   - Auto-layout direction, gaps, padding, alignment, wrapping, sizing modes, constraints, and resizing rules.
   - Layer hierarchy, component instances, variants, properties, states, nested assets, and lock status.
   - Typography family, style, weight, size, line height, letter spacing, alignment, decoration, truncation, and wrapping.
   - Fill, stroke, effect, shadow, blur, opacity, styles, variables, and color values.
   - Prototype flows, triggers, actions, transitions, overlays, scrolling, fixed/sticky behavior, and destinations.
   - Export settings, image assets, icons, illustrations, logos, and implementation dependencies.
7. Capture screenshots whenever the visible panel provides evidence:
   - `layer-structure.png`
   - `design-properties.png`
   - `prototype-properties.png`
   - Additional focused images as `detail-01.png`, `detail-02.png`, and so on.
8. Copy screenshots from the Computer Use screenshot URL into the handout's `assets/` folder. Never alter the Figma file while capturing.
9. Fill `handoud.md` using the required structure below.
10. Verify that every referenced image exists and that observed facts are separated from inference.

## `handoud.md` structure

Use these sections:

```markdown
# <Selection name> — Design Handout

## Source and scope
## Screenshot index
## Directly observed facts
### Geometry and layout
### Layer hierarchy and components
### Typography
### Colors and appearance
### Resizing and constraints
### Prototype and interaction behavior
### Assets and export requirements
## Inferences
## Ambiguities and designer questions
## Implementation guidance
## Completeness checklist
```

For every screenshot, include a relative Markdown image link such as:

```markdown
![Selection overview](assets/selection-overview.png)
```

## Evidence standard

- Label values read from Figma as directly observed.
- Label visually estimated measurements or behavior as inference.
- Never invent exact font, spacing, color, constraint, or interaction values.
- Record inaccessible nested properties as ambiguities rather than silently omitting them.
- If a selection is primarily a screenshot or locked component, document that limitation explicitly.
- Keep absolute canvas coordinates distinct from internal component spacing.

## Completion checks

Before handing off:

- Confirm the source URL and node ID are recorded.
- Confirm `handoud.md` exists.
- Confirm `assets/` contains at least `selection-overview.png`.
- Confirm dimensions, spacing/layout, typography, colors, components/states, resizing rules, interactions, assets, and ambiguities are addressed.
- Confirm observed facts and inferences are clearly separated.
- Confirm no Figma mutation occurred.
