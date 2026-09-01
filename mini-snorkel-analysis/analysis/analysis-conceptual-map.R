# analysis-conceptual-map.R
# Conceptual map of the mini snorkel cover analysis, in the style of
# Jelovica et al. (2024, Ecological Indicators 160:111832) Fig. 3.
# Summarizes the workflow documented in:
#   feather_river_cover_analysis_steelehead.Rmd
#   feather_river_cover_analysis_salmon.Rmd
#
# Data source date ranges (see README.md and feather_river_cover_analysis_salmon.Rmd
# "Redd Data Integration and Exploration" section):
#   Mini Snorkel Data (EDI edi.1705.2): 2001-2002
#   Chinook Redd Survey (EDI edi.1802.2): 2014-2023
#   Steelhead Redd Survey (data-raw/SH Redd Survey.xlsx): 2003-2025
#
# Output: figures/analysis_conceptual_map.png

library(tidyverse)

# ── box + arrow helpers ───────────────────────────────────────────────────

new_box <- function(id, xmin, xmax, ymin, ymax, text, align = "left", fontface = "bold") {
  tibble(
    id = id, xmin = xmin, xmax = xmax, ymin = ymin, ymax = ymax,
    text = text, align = align, fontface = fontface
  )
}

# arrow from the bottom-center of `from` to the top-center of `to`
arrow_down <- function(boxes, from, to) {
  fb <- filter(boxes, id == from)
  tb <- filter(boxes, id == to)
  tibble(x = (fb$xmin + fb$xmax) / 2, y = fb$ymin,
         xend = (tb$xmin + tb$xmax) / 2, yend = tb$ymax)
}

# elbowed arrow used for the exploratory branch that bypasses modeling and
# feeds straight into the left edge of the final results box, mirroring the
# left-hand connector in the source figure
arrow_bypass <- function(boxes, from, to, via_x) {
  fb <- filter(boxes, id == from)
  tb <- filter(boxes, id == to)
  y_target <- (tb$ymin + tb$ymax) / 2
  tibble(
    x    = c((fb$xmin + fb$xmax) / 2, via_x,     via_x),
    y    = c(fb$ymin,                 fb$ymin,   y_target),
    xend = c(via_x,                   via_x,     tb$xmin),
    yend = c(fb$ymin,                 y_target,  y_target)
  )
}

# ── boxes ─────────────────────────────────────────────────────────────────

boxes <- bind_rows(
  new_box("sources", 3, 97, 100, 114,
          paste(
            "Mini Snorkel Data (EDI) — fish counts + habitat covariates (2001–2002)",
            "Redd Survey Data (ground surveys) — Chinook: 2014–2023 · Steelhead: 2003–2025",
            sep = "\n"),
          align = "left"),

  new_box("explore", 1, 48, 74, 96,
          paste(
            "Data Exploration &",
            "Statistical Analysis",
            " ",
            "• High-flow vs. low-flow channel comparison",
            "• Temporal trends (March–August surveys)",
            "• Redd integration — spatial join ≤ 50 m",
            "• Outlier review (count distributions)",
            sep = "\n"),
          align = "left"),

  new_box("variables", 50, 99, 66, 96,
          paste(
            "Habitat Variables of Interest",
            " ",
            "• Numeric: depth, velocity, redd count",
            "• Categorical: month (March–August)",
            "• Redd presence (0/1)",
            "• Cover / substrate → presence-absence",
            "   @ 20% threshold: small/large woody,",
            "   aquatic veg, overhanging veg,",
            "   undercut bank, boulder, cobble",
            sep = "\n"),
          align = "left"),

  new_box("preprocess", 50, 99, 52, 62,
          "Build Model Data\n(threshold cover %, join redd summary,\nremove incomplete records)",
          align = "center"),

  new_box("logistic", 50, 99, 30, 50,
          paste(
            "Candidate Logistic Regression Models",
            "(Steelhead & Chinook Salmon)",
            " ",
            "• Simple GLM",
            "• + (1 | Location)",
            "• + (1 | Channel/Location)",
            "• + (1 | Location) + (1 | Month)",
            "• Steelhead: March–June subset",
            sep = "\n"),
          align = "left"),

  new_box("evaluation", 50, 99, 16, 26,
          # split across two lines - as one line this is the widest string in
          # the figure and overflows the box at the current font size
          "Model Performance Evaluation\nROC / AUC · confusion matrix metrics\nmodel comparison table",
          align = "center"),

  new_box("final", 14, 86, -6, 8,
          paste(
            "Final Model Selection & Inference",
            " ",
            "Best model: (1 | Location) + (1 | Month) random effects",
            "Habitat covariate effect plots (log-odds / odds ratios)",
            "Species-specific results: steelhead & Chinook salmon",
            sep = "\n"),
          align = "center")
)

boxes <- boxes |>
  mutate(
    xc = (xmin + xmax) / 2,
    yc = (ymin + ymax) / 2,
    label_x = if_else(align == "left", xmin + 1.5, xc),
    hjust = if_else(align == "left", 0, 0.5)
  )

# ── arrows ────────────────────────────────────────────────────────────────

arrows <- bind_rows(
  arrow_down(boxes, "sources", "explore"),
  arrow_down(boxes, "sources", "variables"),
  arrow_down(boxes, "variables", "preprocess"),
  arrow_down(boxes, "preprocess", "logistic"),
  arrow_down(boxes, "logistic", "evaluation"),
  arrow_down(boxes, "evaluation", "final"),
  arrow_bypass(boxes, "explore", "final", via_x = 6)
)

# ── plot ──────────────────────────────────────────────────────────────────

p <- ggplot() +
  geom_rect(
    data = boxes,
    aes(xmin = xmin, xmax = xmax, ymin = ymin, ymax = ymax),
    fill = "white", color = "black", linewidth = 0.5
  ) +
  geom_text(
    data = boxes,
    aes(x = label_x, y = yc, label = text, hjust = hjust, fontface = fontface),
    size = 5.2, lineheight = 1.05, family = "serif", vjust = 0.5
  ) +
  geom_segment(
    data = arrows,
    aes(x = x, y = y, xend = xend, yend = yend),
    arrow = arrow(length = unit(0.12, "cm"), type = "closed"),
    linewidth = 0.4
  ) +
  coord_cartesian(xlim = c(0, 100), ylim = c(-8, 116), clip = "off") +
  theme_void() +
  theme(plot.margin = margin(10, 10, 10, 10))

# Height is set generously relative to width: box heights are fixed in data
# units, so the taller canvas is what keeps the larger font from overflowing
# the boxes. Width is unchanged, so the font is genuinely larger relative to
# the figure width (which is what constrains display size in a document).
ggsave(
  here::here("mini-snorkel-analysis", "figures", "analysis_conceptual_map.png"),
  p, width = 11, height = 16, dpi = 300, bg = "white"
)
