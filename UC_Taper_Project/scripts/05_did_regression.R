# =========================================================================
# PROJECT: UC Taper Rate Reform
# SCRIPT: 05_did_regression.R
# AUTHOR: Sophia Adams
# DATE: 07/08/2026
# PURPOSE: Estimate Difference-in-Differences and event-study models of the
# December 2021 UC taper rate cut's effect on claimant employment, and save
# the results as reviewable output files rather than console-only printouts.
#
# OUTCOMES: in_employment_claimants and share_in_employment are modelled as
# two separate, deliberately chosen outcomes -- not a single pooled
# claimant_count spanning both employed and non-employed claimants. If the
# taper cut worked as intended, in_employment_claimants should rise and/or
# not_in_employment_claimants should fall after December 2021, in lower-pay
# ("treated") areas relative to higher-pay ("control") areas.
# =========================================================================

library(tidyverse)
library(fixest)
library(modelsummary)

analysis_panel <- read_csv("data-processed/master_panel_analysis_ready.csv") %>%
  mutate(month_date = as.Date(month_date))

dir.create("outputs", showWarnings = FALSE)

# -------------------------------------------------------------------------
# --- 1. BASELINE TWFE DiD MODELS ---
# Clustered at ttwa_code, not la_code: local authorities within the same
# Travel-to-Work Area share a labour market, so their shocks are unlikely to
# be independent -- clustering at the coarser, economically meaningful
# geography is the more defensible choice here, not the default one.
# -------------------------------------------------------------------------

model_in_employment <- feols(
  in_employment_claimants ~ treat_post | la_code + month_date,
  data = analysis_panel, cluster = ~ttwa_code
)

model_share <- feols(
  share_in_employment ~ treat_post | la_code + month_date,
  data = analysis_panel, cluster = ~ttwa_code
)

model_controls <- feols(
  share_in_employment ~ treat_post + employment_rate_of_active | la_code + month_date,
  data = analysis_panel, cluster = ~ttwa_code
  # hourly_pay_median is deliberately NOT included as a control here -- it's
  # the variable treatment_group was built from, so including it would mean
  # controlling for the very thing that defines "treated," biasing the
  # coefficient rather than cleaning it up.
)

model_not_employment <- feols(
  not_in_employment_claimants ~ treat_post | la_code + month_date,
  data = analysis_panel, cluster = ~ttwa_code
)

summary(model_not_employment)
# -------------------------------------------------------------------------
# --- 2. EVENT-STUDY SPECIFICATION ---
# Interacts treatment with every month relative to November 2021 (the
# reference month, immediately pre-reform), rather than a single "post"
# indicator. This buys two things a single-coefficient model can't: the
# pre-reform coefficients ARE the formal pre-trends test -- indistinguishable
# from zero is direct evidence for parallel trends, not just a visual
# impression from a chart -- and it shows whether the effect builds
# gradually or appears all at once.
# -------------------------------------------------------------------------
event_study <- feols(
  share_in_employment ~ i(month_date, treatment_group, ref = as.Date("2021-11-01")) | la_code + month_date,
  data = analysis_panel, cluster = ~ttwa_code
)

png("outputs/event_study_plot.png", width = 2400, height = 1400, res = 300)
iplot(event_study,
      main = "Event-study: effect of taper cut on share of claimants in employment",
      xlab = "Month (relative to November 2021)")
dev.off()

# -------------------------------------------------------------------------
# --- 3. RESULTS TABLE, SAVED TO FILE ---
# A results table sitting only in a console pane disappears the moment the
# session closes -- saving it is what makes this a genuine, reviewable
# output someone else can actually see without re-running the code.
# -------------------------------------------------------------------------
modelsummary(
  list(
    "In-employment claimants" = model_in_employment,
    "Not in-employment claimants" = model_not_employment,
    "Share in employment" = model_share,
    "With employment rate control" = model_controls
  ),
  stars = TRUE,
  gof_omit = "IC|LogLik|F|Std.Errors",
  title = "Effect of the December 2021 UC taper rate cut on claimant employment",
  output = "outputs/did_results_table.docx"
)

summary(model_in_employment)
summary(model_share)
summary(model_controls)