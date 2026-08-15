# =========================================================================
# PROJECT: UC Taper Rate Reform
# SCRIPT: 03_build_analysis_variables.R
# AUTHOR: Sophia Adams
# DATE: 07/08/2026
# PURPOSE: Turn the joined SQL panel into one analysis-ready file: reshaped
#          from one row per LA-month-employment-status into one row per LA-month, with
#          the DiD design variables (post, treatment_group, treat_post) built exactly
#          once, so every downstream script reads an identical definition of both.
# =========================================================================

library(tidyverse)

master_panel <- read_csv("data-processed/master_labour_panel.csv") %>%
  mutate(
    month_date = as.Date(month_date),
    hourly_pay_median = as.numeric(hourly_pay_median),
    weekly_hours_median = as.numeric(weekly_hours_median)
  )

# -------------------------------------------------------------------------
# --- 1. RESHAPE TO ONE ROW PER LA-MONTH ---
# employment_status currently splits each LA-month across two rows ("in
# employment" / "not in employment"), sharing one claimant_count column. A
# regression run directly on that would treat both as the same kind of
# observation. Pivoting to wide format turns employment status into two
# properly separate, named outcome columns instead.
# -------------------------------------------------------------------------
wide_panel <- master_panel %>%
  pivot_wider(
    id_cols = c(month_date, year, ttwa_code, ttwa_name, la_code, la_name,
                economically_active, in_employment, employment_rate_of_active,
                hourly_pay_median, weekly_hours_median),
    names_from = employment_status,
    values_from = claimant_count
  ) %>%
  rename(
    in_employment_claimants = `In employment (PAYE) or self-employment`,
    not_in_employment_claimants = `Not in employment (PAYE) or self-employment`
  ) %>%
  mutate(
    total_claimants = in_employment_claimants + not_in_employment_claimants,
    share_in_employment = in_employment_claimants / total_claimants
  )

wide_panel %>% filter(is.na(hourly_pay_median)) %>% distinct(la_code) %>% nrow()

# -------------------------------------------------------------------------
# --- 2. BUILD THE DiD DESIGN VARIABLES ---
# Treatment classification is fixed and computed once here, using only the
# 2021 (pre-reform) pay level -- already the sole year present in
# hourly_pay_median thanks to the SQL join -- so it cannot drift depending on
# which year a given row falls in. Computed from the DISTINCT set of areas,
# not the full panel, to make clear this classifies AREAS, not area-months.
# -------------------------------------------------------------------------
la_pay_median <- wide_panel %>%
  distinct(la_code, hourly_pay_median) %>%
  summarise(median_pay = median(hourly_pay_median, na.rm = TRUE)) %>%
  pull(median_pay)

analysis_panel <- wide_panel %>%
  mutate(
    post = if_else(month_date >= as.Date("2021-12-01"), 1, 0),
    # Below-median 2021 pay = higher exposure to the taper cut, since a given
    # percentage-point reduction in the taper rate is worth more in cash
    # terms, relative to income, to lower-paid claimants.
    treatment_group = if_else(hourly_pay_median < la_pay_median, 1, 0),
    treat_post = treatment_group * post
  ) %>%
  filter(!is.na(treatment_group))  # Drops areas with missing 2021 pay data entirely, rather than letting them surface as a misleading third "NA" group in later charts

print(paste("Analysis panel rows:", nrow(analysis_panel)))
print(paste("Treatment group split:", sum(analysis_panel$treatment_group == 1, na.rm = TRUE), "treated rows /",
            sum(analysis_panel$treatment_group == 0, na.rm = TRUE), "control rows"))

write_csv(analysis_panel, "data-processed/master_panel_analysis_ready.csv")