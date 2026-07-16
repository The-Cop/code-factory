---
name: "deck-dna"
description: "Use when the user needs to build a brand-accurate PowerPoint (PPTX) deck that looks like their real client or brand reference decks, not a generic template. Extracts design DNA from reference decks, calibrates a word budget, embeds real backgrounds and fonts so it renders identically anywhere, and runs a render-QA loop. Triggers: \"build a deck\", \"make slides\", \"pptx\", \"powerpoint deck\", \"brand deck\", \"client deck\", \"presentation that matches our brand\", \"deck-dna\"."
---

# deck-dna - decks that sit next to your real reference decks without looking out of place

Announce: "I'm using the /deck-dna skill to build a brand-accurate deck from your reference decks."

This is a method, not a fixed brand. It ships with Datadog brand DNA as the built-in default (see the next section); pass your own reference decks to build for any other brand and the method extracts fresh DNA from those instead. There is nothing to install beyond Python itself: every helper script this skill needs is written inline below and created on the fly when it's needed. You (or whoever is running this skill for you) don't need to manage separate script files.

Brand-compliant is not the same as designed. A deck in the right colors with plain text boxes passes any style guide and still looks like a template. The thing that separates a designed deck from a flat one is composition: full-bleed imagery, a deliberate content zone, hero-weight stats, chaptering. Extract that from decks that already look right, don't invent it.

## Inputs

Parse `$ARGUMENTS` for reference deck paths (`.pptx`) and any brand or output description. Resolve the brand DNA like this:

- If one or more `.pptx` paths are supplied in `$ARGUMENTS`, run Steps 1 and 2 to extract fresh DNA (colors, fonts, backgrounds, word budget) from those decks.
- If none are supplied, use the built-in Datadog brand DNA in the next section. It was already extracted with the Step 1 and 2 methods, so skip straight to building (Step 3).

This method extracts from real decks and never invents a brand. If a supplied reference path does not exist, report it and stop rather than substituting anything.

## Built-in brand DNA: Datadog (default)

Use these values directly when no reference decks are passed. They were extracted from an approved 2023 Datadog template (104 slides, 36 layouts, 1 master) using the Step 1 and 2 methods, eyedropped off the actual slides and master rather than the theme block. The theme block was a stale generic palette in Arial: the exact master-override trap Step 1 warns about, so it was discarded.

Canvas: 16:9 widescreen, 13.33 in x 7.5 in (12188950 x 6858000 EMU). Light canvas by default (white, with #F2F2F2 panels), black body text.

Fonts (all embedded in the source deck as `.fntdata`, so embed them the same way per Step 4):
- Roboto: display and body (Regular, Medium, Bold, Italic). "Roboto Medium" is used as its own weight.
- Roboto Mono: code, data, and mono labels.
- Ignore Arial: it only appears as a fallback and in the stale theme block.
- Licensing: Roboto and Roboto Mono are Apache 2.0, so embedding and redistributing them is fine (the Step 4 font-licensing caveat is already cleared for this default).

Colors (hex eyedropped from actual slides and the master):
- Primary accent: #4F00FF (electric indigo). Secondary purple: #7700FF. Mid purple: #6B27AC.
- Purple wash / tint fills: #E1CCF4 (lavender).
- Neutrals: #000000 text, #FFFFFF, #F2F2F2 (light gray panels), grays #D4D7DA / #BFC4C8 / #BFBFBF.
- Warm accents (use sparingly): #F26B43 (orange), #FBAE40 (amber), #FF0078 (magenta).
- Data/chart series (teal-green family): #00A79D, #23C2AA, #32CEB0, #3EB2A4, #48B882, #53BE61, #05A82D. Dark blues: #1E407C, #003175.
- Do NOT use the theme1.xml palette (#058DC7, #50B432, #ED561B, #EDEF00, #24CBE5, #64E572): it is a stale generic default that does not match the slides.

Composition: light canvas with occasional full-bleed hero/divider slides (about 1 in 5 slides carries a full-bleed image or solid purple panel). Alternate low-density purple dividers with 2-3 lighter data slides, per Step 1 chaptering.

Word budget (measured per Step 2, text frames only, tables excluded, across 104 slides): mean 30, median 20, Q3 41, max 134. Ceiling for a new build: about 25 words per slide (median rounded up); allow dense data slides up to ~40, everything included, source line counts.

## Restrictions and hard rules (read first)

- Don't invent or embellish data on a slide. This skill styles numbers, it never upgrades them. If the numbers came from someone else's analysis, keep their sourcing and caveats intact on the slide or in the source line.
- Name every data source on a slide. If a slide mixes data from two different sources or methodologies, name both in its source line: don't let one attribution imply the other applies to all the numbers.
- Never invent brand assets. Don't redraw or re-rasterize a logo from memory, don't invent a color or font because it "seems right," and don't use AI-generated or stock-web imagery if the reference decks use real brand photography: it will look like a mismatch. If a required asset (logo, font, background) isn't supplied, stop and ask for it rather than substituting something.
- Client-facing vs. internal changes what content is safe to show, not how much design effort goes in. Build the internal version to the same visual standard as anything going to a client.
- Never ship denser than the measured word budget (see Step 2). Cut content or split the slide: don't shrink the font to cram more text in; that's the flat-template tell.
- Never build on top of an existing reference deck (see Step 3): it drags in every unused layout/master slide that file ever had.
- Font licensing is not automatic. If you extract and embed a font from someone else's deck, check you're actually covered to redistribute it before shipping the new deck to a client.

## Step 0: Check your tools before you build

This method needs `python-pptx` and `Pillow` to build at all. LibreOffice + Poppler are needed only for the automated QA-render step in Step 5: if they're not available, there's a manual fallback (open the deck directly in PowerPoint/Keynote/Google Slides and review slide by slide).

Before the first build, create and run this check:

```python
# preflight_check.py
import importlib.util, shutil, sys

required = [("pptx", "python-pptx", "pip install python-pptx"),
            ("PIL", "Pillow", "pip install Pillow")]
qa_tools = [("soffice", "LibreOffice", "https://www.libreoffice.org/download/download/"),
            ("pdftoppm", "Poppler", "brew install poppler / apt install poppler-utils / https://poppler.freedesktop.org/")]

def find_tool(exe):
    import os
    hit = shutil.which(exe)
    if hit: return hit
    # macOS: LibreOffice ships soffice inside the app bundle, not on PATH
    p = f"/Applications/LibreOffice.app/Contents/MacOS/{exe}"
    if os.path.exists(p): return p
    return None

missing_required = [(l, h) for m, l, h in required if importlib.util.find_spec(m) is None]
missing_qa = [(l, h) for e, l, h in qa_tools if find_tool(e) is None]

for m, l, h in required:
    print(f"[{'OK' if importlib.util.find_spec(m) else 'MISSING'}] {l}")
for e, l, h in qa_tools:
    hit = find_tool(e)
    print(f"[{'OK: ' + hit if hit else 'MISSING'}] {l}")

if missing_required:
    print("\nCannot build without these:")
    for l, h in missing_required: print(f"  - {l}: {h}")
    sys.exit(1)
if missing_qa:
    print("\nCan build, but no automated QA render. Fallback: review the .pptx by hand, slide by slide.")
    for l, h in missing_qa: print(f"  - missing {l}: {h}")
```

Run it, fix anything flagged as missing under "Cannot build without these," and note whether the QA tools are present (that decides whether Step 5 runs automated or manual).

## Step 1: Extract your design DNA from your own reference decks

Run this step only when you passed your own reference decks (using the built-in Datadog DNA? it's done, skip to Step 3). Pick 2-3 decks that already look right for your brand or client (decks someone has approved, not a generic template). Note down, before writing any build code:

- Composition: where does imagery sit relative to text? (full-bleed bleeding from one side, split-panel, imagery as background texture, etc.) This is usually the single biggest gap between "looks designed" and "looks like a template."
- Colors: exact hex values pulled from the actual slides with an eyedropper, not the theme's stated accent color: deck themes frequently have a stated accent that doesn't match what's actually on the slides because of master-slide overrides.
- Fonts: what's actually embedded in the file (unzip the `.pptx`, check the `ppt/fonts/` folder) vs. what's just referenced by name. An unembedded font can render as a bad substitution on someone else's machine.
- Recurring elements: footer treatment, section-badge style, how a "big stat" is presented vs. a small one, bullet style, source-line format and placement.
- Chaptering: full-bleed divider slides between sections, or just headers? Reference decks usually alternate: a low-density divider, then 2-3 data slides, repeat. A wall of data slides in a row reads as a spreadsheet.

Write this down as a short DNA sheet before building anything.

## Step 2: Calibrate your word budget from the same references

Don't guess a words-per-slide target: measure it. Create and run this against your reference files:

```python
# calibrate_word_budget.py
import statistics, sys
from pptx import Presentation

def words_per_slide(path):
    prs = Presentation(path)
    return [(path, i, sum(len(sh.text_frame.text.split()) for sh in slide.shapes if sh.has_text_frame))
            for i, slide in enumerate(prs.slides, start=1)]

all_counts = []
for path in sys.argv[1:]:
    counts = words_per_slide(path)
    all_counts.extend(counts)
    values = [c for _, _, c in counts]
    print(f"{path}: {len(values)} slides, mean {statistics.mean(values):.1f}, median {statistics.median(values):.0f}, max {max(values)}")

values = [c for _, _, c in all_counts]
print(f"\nCombined: mean {statistics.mean(values):.1f}, median {statistics.median(values):.0f} words/slide")
top3 = sorted(all_counts, key=lambda x: -x[2])[:3]
print("Densest 3 slides (check whether these are outliers to exclude):")
for path, idx, count in top3:
    print(f"  {path} slide {idx}: {count} words")
```

Usage: `python calibrate_word_budget.py <ref1.pptx> <ref2.pptx> ...` (quote any path that contains a space). One limit: the script counts text boxes only, not text inside tables, so if your reference decks are table-heavy treat the measured number as a floor. Use the resulting median, rounded up slightly, as your ceiling for the new build, not the mean, since a couple of dense outlier slides shouldn't set the target. Restate it as a single rule before building: "<=N words per slide, everything included, source line counts." After building, rerun the same word-count logic on the new deck and cut anything over budget.

## Step 3: Build fresh, don't build on top of a reference deck

Build on a blank `python-pptx` presentation. Write small reusable components matching what you found in Step 1: a base canvas (background treatment + footer + source line), a content-zone text block, a hero-stat block, a small-stat block, a badge, a bullet style. Reuse these across slides, but vary the layout (grid vs. single hero vs. ranked list vs. stacked rows) slide to slide so the deck doesn't read as one template stamped repeatedly.

Craft rules for display type and stats (every one of these was a real reviewer catch, not theory):

- Control every line break in display type (anything above ~28pt). Never let autowrap decide: split long headlines into explicit lines, and set no-wrap on stat boxes so a digit can't spill. In QA, hunt for widows (a one-word last line), and a dangling article at a line end ("open a / dashboard"): classic tells a typesetter would never allow.
- Subordinate the unit glyph on hero stats. Render %, x, $ at 50-60% of the numeral size on the same baseline, tight to the last digit. A full-size unit next to a huge numeral reads pasted-on.
- Charts win or lose the credibility argument. Flat fills, direct labels on the bars (no legend), no gridline noise, zero baseline with visually accurate proportions, accent color only on the focal series or current period. Skeptics ask for a chart before anything else.

## Step 4: Treat and embed your own assets

Backgrounds: if the DNA sheet calls for full-bleed photography, treat raw images so text sits on a legible zone rather than directly on a busy photo:

```python
# treat_bg.py - directional darken + fade-to-black, so text sits on a clean zone
import sys
from PIL import Image, ImageDraw, ImageEnhance

W, H = 1920, 1080

def treat(src, dst, darken=0.52, fade_end=0.58, solid=0.08):
    im = Image.open(src).convert("RGB").resize((W, H))
    im = ImageEnhance.Brightness(im).enhance(darken)
    if fade_end > 0:
        grad = Image.new("L", (W, H), 0); gd = ImageDraw.Draw(grad)
        for x in range(W):
            t = x / W
            a = 255 if t < solid else 0 if t > fade_end else int(255 * (1 - (t - solid) / (fade_end - solid)))
            gd.line([(x, 0), (x, H)], fill=a)
        im = Image.composite(Image.new("RGB", (W, H), (0, 0, 0)), im, grad)
    im.save(dst, quality=86)

if __name__ == "__main__":
    a = sys.argv
    treat(a[1], a[2], float(a[3]) if len(a) > 3 else 0.52, float(a[4]) if len(a) > 4 else 0.58)
```

Prefer flat, hard-edged shapes over soft radial glows: gradient smears and faint diagonal hatching have become a recognized signature of AI-generated decks. If you use a glow, blend it at low opacity so it reads as ambient texture, not effect. The script assumes 16:9 source images (it resizes to 1920x1080 without cropping), so crop non-16:9 images to 16:9 first or they'll look squashed. And never repeat the same background across slides in one deck if more than one option exists: repetition reads as template laziness.

Fonts: if your reference decks embed fonts (checked in Step 1), do the same so the deck renders true on any machine. This requires a one-time setup per brand: extract the font parts (`.fntdata` files) plus the `embeddedFontLst.xml` and font-relationship XML from an already-embedded, licensed reference deck (unzip its `.pptx` and look in `ppt/fonts/` and `ppt/presentation.xml`). That extracted package then gets injected into new builds as a post-build step. This is fiddly XML surgery: if you're not comfortable with it, skip embedding and instead confirm the fonts are installed on every machine that will open the deck, and flag that as a known limitation.

## Step 5: QA render loop (mandatory - decks always look different rendered than in the editor)

If Step 0 found LibreOffice + Poppler:
1. `soffice --headless --convert-to pdf deck.pptx` (on macOS, `soffice` is usually not on PATH; use the full path Step 0 printed, e.g. `/Applications/LibreOffice.app/Contents/MacOS/soffice`)
2. `pdftoppm -jpeg -r 150 deck.pdf slide`
3. Look at every resulting slide image for text collisions, unexpected wrapping, overlapping elements, footer/margin spacing.

If either tool is missing: open the deck directly in PowerPoint/Keynote/Google Slides and step through every slide by hand for the same checks. Either way, do one final visual pass in the actual presentation app before sending: if a font isn't installed on the QA machine, LibreOffice substitutes something else, so its render is approximate on spacing/wrapping even when the file itself is correct.

## Step 6: Adversarial design review (optional but the single biggest quality jump)

After the render QA passes, hand the slide images to a second agent for a fresh-eyes review. Dispatch it with the subagent tool (a general-purpose subagent) using this one-line brief: "You are a harsh senior presentation designer reviewing a portfolio. Approve only what a working designer would ship, name every amateur tell, and do not soften." Fix what it flags, re-render, send it back. Expect two or three rounds; that is the process working, not failing.

This step exists because the builder cannot see its own tells. In the build this method comes from, the reviewer rejected the first demo set outright (a system font posing as a brand look, gradient smears, a floating unaligned shape) and approved it two rounds later: none of those catches were visible from inside the build.

## Worked example

This method was extracted from a real build for a media-sales brand (full-bleed lifestyle photography fading to black on one side, a single accent color, two embedded font families, a badge-based section system, a fixed footer). That brand's specific colors, fonts, and word-count numbers aren't included here: they belong to that brand, not to this method. What transferred into this file is the process: preflight check, extract-your-own-DNA, calibrate-then-build, treat-then-embed, render-then-QA. Running Steps 1 and 2 on your own reference decks will produce different numbers, and that's the point.

## Error Handling

| Error | Action |
|-|-|
| No reference decks supplied in `$ARGUMENTS` | Not an error. Use the built-in Datadog brand DNA and skip to Step 3. |
| `python-pptx` or `Pillow` missing (Step 0) | Cannot build. Print the `pip install` command from preflight and stop until installed. |
| LibreOffice or Poppler missing (Step 0) | Continue building, but Step 5 runs manually. Warn the user that automated QA render is unavailable. |
| Reference deck path does not exist or is not `.pptx` | Report the exact path, list the paths that did resolve, and ask for a correction. |
| Required asset (logo, font, background) not supplied | Stop and ask for it. Do not substitute AI-generated, stock, or from-memory assets. |
| Source image is not 16:9 | Crop to 16:9 before running `treat_bg.py`, or it will look squashed. |
| Font not licensed for redistribution | Do not embed. Fall back to confirming the font is installed on every target machine and flag it as a known limitation. |
| New deck exceeds the measured word budget (Step 2) | Cut content or split the slide. Never shrink the font to cram text in. |
| QA render shows collisions, widows, or overlaps | Fix in the build code and re-render. Repeat Step 5 until clean; do not hand-edit the rendered images. |
