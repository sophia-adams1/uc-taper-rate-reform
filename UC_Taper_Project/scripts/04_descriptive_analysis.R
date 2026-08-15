# =========================================================================
# PROJECT: UC Taper Rate Reform
# SCRIPT: 04_descriptive_analysis.R
# AUTHOR: Sophia Adams
# DATE: 07/08/2026
# PURPOSE: Summarise the analysis-ready panel, visualise the claimant trend
# split by exposure group, and formally test the parallel pre-trends
# assumption the DiD design in 05_did_regression.R depends on.
# =========================================================================

library(tidyverse)
library(scales)

analysis_panel <- read_csv("data-processed/master_panel_analysis_ready.csv") %>%
  mutate(month_date = as.Date(month_date))

dir.create("outputs", showWarnings = FALSE) # Ensures the output folder exists on a fresh clone, not just on this machine

# --- 1. SUMMARY STATISTICS ---
summary_stats <- analysis_panel %>%
  summarise(
    mean_in_employment_claimants = mean(in_employment_claimants, na.rm = TRUE),
    mean_share_in_employment = mean(share_in_employment, na.rm = TRUE),
    mean_pay_2021 = mean(hourly_pay_median, na.rm = TRUE),
    mean_employment_rate = mean(employment_rate_of_active, na.rm = TRUE)
  )
print(summary_stats)

# -------------------------------------------------------------------------
# --- 2. TREND, SPLIT BY EXPOSURE GROUP ---
# Split by treatment_group rather than plotted as one national line -- a
# single aggregate trend can't show whether the two groups were moving
# together before the reform, which is the whole point of checking this.
# -------------------------------------------------------------------------
trend_data <- analysis_panel %>%
  group_by(month_date, treatment_group) %>%
  summarise(mean_share_in_employment = mean(share_in_employment, na.rm = TRUE), .groups = "drop") %>%
  mutate(treatment_group = factor(treatment_group, labels = c("Control (higher 2021 pay)", "Treated (lower 2021 pay)")))

trend_plot <- ggplot(trend_data, aes(x = month_date, y = mean_share_in_employment, color = treatment_group)) +
  geom_line(linewidth = 1.1) +
  geom_point(size = 1.6) +
  geom_vline(xintercept = as.Date("2021-12-01"), linetype = "dashed", color = "grey30") +
  labs(
    title = "Share of UC claimants in employment, by exposure group",
    subtitle = "Dashed line marks the December 2021 taper rate reform",
    x = NULL, y = "Share of claimants in employment", color = NULL
  ) +
  theme_minimal() +
  scale_y_continuous(labels = label_percent()) +
  theme(legend.position = "bottom")

ggsave("outputs/trend_by_treatment_group.png", trend_plot, width = 8, height = 5, dpi = 300)
print(trend_plot)

# -------------------------------------------------------------------------
# --- 3. FORMAL PARALLEL PRE-TRENDS CHECK ---
# Restricted to the pre-reform period only, then tests whether the treated
# and control groups' trends differ BEFORE treatment even happened. A
# significant treatment_group:month_date interaction here would flag that
# the two groups weren't on comparable paths to begin with -- a standard
# check any reviewer of a DiD design expects to see, not an optional extra.
# -------------------------------------------------------------------------
pretrend_data <- analysis_panel %>% filter(post == 0)

pretrend_test <- lm(share_in_employment ~ treatment_group * month_date, data = pretrend_data)
cat("\n--- Pre-trend check (pre-reform period only) ---\n")
cat("A non-significant treatment_group:month_date coefficient supports the parallel trends assumption:\n")
print(summary(pretrend_test)$coefficients)