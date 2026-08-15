# =========================================================================
# PROJECT: UC Taper Rate Reform
# SCRIPT: 01_clean_raw_datasets.R
# AUTHOR: Sophia Adams
# DATE: 07/08/2026
# PURPOSE: Transform the raw Stat-Xplore UC claimant export and the raw NOMIS
#          APS employment export into two clean, analysis-ready CSVs, so the SQL join
#          in 02_build_panel_data.sql has consistent, well-typed inputs to work with.
# =========================================================================

# --- 1. LOAD LIBRARIES ---

library(tidyverse) # Data wrangling and pivoting
library(lubridate) # Parsing the "Month Year" text strings the raw file uses into real dates

# -------------------------------------------------------------------------

# --- 2. UC CLAIMANT COUNT DATA ---

# DWP's Stat-Xplore exports are commonly Windows-1252 encoded rather than
# UTF-8 -- without specifying this, Welsh council names containing accented
# characters (e.g. "Ynys Môn") fail to parse correctly.
raw_uc <- read_csv("data-raw/UC_Regional_2021_2022.csv", 
                   locale = locale(encoding = "windows-1252"))

uc_clean <- raw_uc %>%
  select(-1) %>%                                                     # Dropped empty leading column
  rename(la_name = 1, employment_status = 2) %>%                     # Renamed columns to consistent, code-friendly names
  filter(employment_status != "Employment Indicator (V)") %>%        # Dropped a leftover header artefact row
  fill(la_name, .direction = "down") %>%                             # LA name only appears once per 3-row block; filled it down
  filter(!is.na(employment_status)) %>%                              # Dropped trailing blank rows
  filter(!la_name %in% c("Great Britain", "Total", "Unknown")) %>%   # Dropped aggregate/residual rows -- not real local authorities
  mutate(la_name = sub(" / .*$", "", la_name)) %>%                   # Welsh LAs come through as "English / Welsh" -- kept the English form to match the geography lookup
  filter(employment_status != "Total") %>%                           # Kept only the two real employment categories
  pivot_longer(cols = -c(la_name, employment_status), names_to = "month", values_to = "claimant_count") %>% # Reshaped 24 month columns into one long column
  mutate(
    claimant_count = as.numeric(gsub(",", "", claimant_count)),      # Stripped thousands separators before converting to numeric
    date = my(month),                                                # Parsed "January 2021"-style strings into real dates
    year = year(date)                                                # Extracted year separately for later year-matched joins
  ) %>%
  select(la_name, employment_status, date, year, claimant_count)     # Final column order

# Guards against a silent geography mismatch further down the pipeline --
# if a future re-download changes area coverage, this stops the script here
# rather than letting a corrupted panel pass through unnoticed.
stopifnot(n_distinct(uc_clean$la_name) == 350)

write_csv(uc_clean, "data-processed/uc_regional_clean.csv")

# -------------------------------------------------------------------------

# --- 3. NOMIS APS DATA ---

# This file is actually two separate NOMIS query exports (2021 and 2022)
# pasted into a single CSV, each with its own metadata block and header row
# in the middle of the file -- read as plain text lines first so the header
# positions can be located before attempting to parse it as a table.
raw_lines <- read_lines("data-raw/aps_employment_2021_2022.csv")
header_row_positions <- grep("^local authority", raw_lines)

# Extracts one year's block cleanly, bypassing the embedded metadata around
# it. Written as a function rather than duplicated code, so if NOMIS changes
# its export format, there's exactly one place to fix it.
read_aps_block <- function(start_line, end_line, year_label) {
  block <- read.csv(
    text = paste(raw_lines[start_line:end_line], collapse = "\n"),
    header = TRUE, check.names = FALSE
  )
  
  # This file has genuinely blank-named spacer columns (between each count
  # column and its confidence-interval column). dplyr's rename()/select()
  # validate every column name up front and error on truly empty ones, even
  # ones left untouched -- so columns are named by base R position first,
  # then subset down to just the four actually needed.
  names(block)[c(1, 2, 3, 6)] <- c("la_name", "la_code", "economically_active", "in_employment")
  block <- block[, c("la_name", "la_code", "economically_active", "in_employment")]
  
  block %>%
    filter(str_detect(la_code, "^[EW]"), !str_detect(la_name, "^\\*"))  %>% # Keeps only real England/Wales area codes -- drops footnote and legend rows in one step
    mutate(      # Keeps only real England/Wales area codes -- drops footnote and legend rows in one step
      economically_active = as.numeric(gsub(",", "", economically_active)), # Stripped thousands separators
      in_employment = as.numeric(gsub(",", "", in_employment)),             # Stripped thousands separators
      employment_rate_of_active = in_employment / economically_active,      # In-employment share of the economically active population
      year = year_label                                                    # Tagged with the correct year, since the raw file has no year column of its own
    ) %>%
    select(la_name, la_code, year, economically_active, in_employment, employment_rate_of_active)
}

# Applies the extraction function to both the 2021 and 2022 blocks and
# stacks them into one long, properly year-labelled dataset.
aps_clean <- bind_rows(
  read_aps_block(header_row_positions[1], header_row_positions[2] - 1, 2021),
  read_aps_block(header_row_positions[2], length(raw_lines), 2022)
)

write_csv(aps_clean, "data-processed/aps_employment_clean.csv")
