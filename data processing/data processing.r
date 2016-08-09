########################################################################
# Calculate D1 scores, accuracy and latency summary statistics for the 
# Open Source IRAP (Implicit Relational Assessment Procedure)
########################################################################
# Author: 
# Ian Hussey (ian.hussey@ugent.be)

# Version:
# 0.6

# Usage:
# Simply set the input directory [the line containing setwd()] and 
# output directory [the line containing write.csv()] and run script.
# See README for notes.

# To do:
# 1. quantify participants who fail prac blocks. currently they appear as 
# N prac blocks = (max) and with no test block data.

########################################################################
# Clean workspace
rm(list=ls())

########################################################################
# Dependencies
library(plyr)
library(dplyr)
library(tidyr)
library(data.table)

# NB Given the shared namespaces between plyr and dplyr (e.g., both 
# contain functions called "rename"), this script specifies which 
# library's function is to be called. Usually, loading plyr before dplyr 
# (as done above) prevents any issues, but this method is safer.

########################################################################
# Data acquisition and cleaning
setwd("~/git/Open Source IRAP/data")
files <- list.files(pattern = "\\.csv$")
input_df <- tbl_df(rbind.fill(lapply(files, fread, header=TRUE)))  # tbl_df() requires dplyr, rbind.fill() requires plyr, fread requires data.table

# One of two columns that are later needed are created depending on the block order condition.
# Check if each exists, and create them if not and set to NA.  
if("trials_Afirst.thisTrialN" %in% colnames(input_df)){
  # column already exists: do nothing.
} else {
  input_df[,"trials_Afirst.thisTrialN"] <- NA
}

if("trials_Asecond.thisTrialN" %in% colnames(input_df)){
  # column already exists: do nothing.
} else {
  input_df[,"trials_Asecond.thisTrialN"] <- NA
}

# If participants fail the practice blocks, this column will also be absent. 
# Create it so that n who failed prac blocks can be quantified.  
if("trials_B.thisTrialN" %in% colnames(input_df)){
  # column already exists: do nothing.
} else {
  input_df[,"trials_B.thisTrialN"] <- NA
}

# Make some variable names more transparent, plus rectify the the accuracy variable
cleaned_df <- 
  dplyr::rename(input_df,
         trial_type = trialType,
         practice_block_pair = practice_blocks.thisRepN,
         test_block_pair = test_blocks.thisRepN,
         trial_order_a_first = trials_Afirst.thisTrialN,
         trial_order_a_second = trials_Asecond.thisTrialN,
         trial_order_b = trials_B.thisTrialN,
         rt_a = required_response_A.rt,
         rt_b = required_response_B.rt,
         accuracy_a = feedback_response_A.corr,
         accuracy_b = feedback_response_B.corr,
         starting_block = StartingBlock,
         latency_criterion = latencyCriterion,
         accuracy_criterion = accuracyCriterion,
         auto_response_monkey = UseMonkey) %>%
  rowwise() %>%  # needed for the row-wise mutate() for rt and accuracy below 
  dplyr::mutate(accuracy_a = abs(accuracy_a - 1),  # recitfies the direction of accuracy so that 0 = error and 1 = correct.
         accuracy_b = abs(accuracy_b - 1),
         practice_block_pair = practice_block_pair + 1,  # recifies block to start at 1
         test_block_pair = test_block_pair + 1,
         rt = sum(rt_a, rt_b, na.rm=TRUE),  # get all rts in one column 
         accuracy = sum(accuracy_a, accuracy_b, na.rm=TRUE),  # get all accuracies in one column. only one block will be present per row.
         trial_order = sum(trial_order_a_first, trial_order_a_second, trial_order_b, na.rm = TRUE)) %>%  # get all trial_order in one column. only one block will be present per row.
  ungroup() %>%  # removes rowwise
  select(participant,
         starting_block,
         practice_block_pair,
         test_block_pair,
         trial_order,
         trial_type,
         rt_a,
         rt_b,
         rt,
         accuracy_a,
         accuracy_b,
         accuracy,
         accuracy_criterion,
         latency_criterion,
         age,
         gender,
         date,
         max_pairs_practice_blocks,
         n_pairs_test_blocks,
         moving_response_options,
         auto_response_monkey)

########################################################################
# demographics and test parameters 
demographics_df <-
  select(cleaned_df,
         participant,
         gender,
         age,
         date,
         starting_block,
         max_pairs_practice_blocks,
         n_pairs_test_blocks,
         latency_criterion,
         accuracy_criterion,
         moving_response_options,
         auto_response_monkey) %>%
  distinct(participant, .keep_all = TRUE)

n_pairs_practice_blocks_df <-
  group_by(cleaned_df, 
           participant) %>%
  dplyr::summarize(n_pairs_practice_blocks = max(practice_block_pair, na.rm = TRUE))

########################################################################
# D1 scores (following Greenwald et al., 2003) and mean latency

# D1 calculated from all test block rts
D1_df <-  
  group_by(cleaned_df, 
           participant) %>%
  filter(rt <= 10000 &
           !is.na(test_block_pair)) %>%  # test blocks only
  dplyr::summarize(rt_a_mean = mean(rt_a, na.rm = TRUE),
            rt_b_mean = mean(rt_b, na.rm = TRUE),
            rt_mean = mean(rt),
            rt_sd = sd(rt),
            rt_block_A_median = median(rt_a, na.rm = TRUE),
            rt_block_B_median = median(rt_b, na.rm = TRUE)) %>%
  dplyr::mutate(diff = rt_b_mean - rt_a_mean,
         D1 = round(diff / rt_sd, 2),
         rt_mean = round(rt_mean, 3),  # rounding for output simplicity is done only after D1 score calculation
         rt_sd = round(rt_sd, 3),
         rt_block_A_median = round(rt_block_A_median, 3),
         rt_block_B_median = round(rt_block_B_median, 3)) %>% 
  select(participant, 
         rt_mean,
         rt_sd,
         rt_block_A_median,
         rt_block_B_median,
         D1)

# D1 calculated for each of the four trial-types from all test block rts
D1_by_tt_df <-  
  group_by(cleaned_df, 
           participant,
           trial_type) %>%
  filter(rt <= 10000 &
           !is.na(test_block_pair)) %>%  # test blocks only
  dplyr::summarize(rt_a_mean = mean(rt_a, na.rm = TRUE),
            rt_b_mean = mean(rt_b, na.rm = TRUE),
            rt_sd = sd(rt)) %>%
  dplyr::mutate(diff = rt_b_mean - rt_a_mean,
         D1_by_tt = round(diff / rt_sd, 2)) %>%
  select(participant, 
         trial_type,
         D1_by_tt) %>%
  spread(trial_type, D1_by_tt) %>%
  dplyr::rename(D1_trial_type_1 = `1`,
         D1_trial_type_2 = `2`,
         D1_trial_type_3 = `3`,
         D1_trial_type_4 = `4`)

# D1 for ODD trials by order of presentation (for split half reliability) calculated from all test block rts
D1_odd_df <-  
  group_by(cleaned_df, 
           participant) %>%
  filter(rt <= 10000 &
           !is.na(test_block_pair) &  # test blocks only
           trial_order %% 2 == 0) %>%  # odd trials only, nb count starts at 0
  dplyr::summarize(rt_a_mean = mean(rt_a, na.rm = TRUE),
            rt_b_mean = mean(rt_b, na.rm = TRUE),
            rt_sd = sd(rt)) %>%
  dplyr::mutate(diff = rt_b_mean - rt_a_mean,
         D1_odd = round(diff / rt_sd, 2)) %>%
  select(participant, 
         D1_odd)

# D1 for EVEN trials by order of presentation (for split half reliability) calculated from all test block rts
D1_even_df <-  
  group_by(cleaned_df, 
           participant) %>%
  filter(rt <= 10000 &
           !is.na(test_block_pair) &  # test blocks only
           trial_order %% 2 == 1) %>%  # odd trials only, nb count starts at 0
  dplyr::summarize(rt_a_mean = mean(rt_a, na.rm = TRUE),
            rt_b_mean = mean(rt_b, na.rm = TRUE),
            rt_sd = sd(rt)) %>%
  dplyr::mutate(diff = rt_b_mean - rt_a_mean,
         D1_even = round(diff / rt_sd, 2)) %>%
  select(participant, 
         D1_even)

########################################################################
# Percentage accuracy and percentage fast trials 
## exclusions based on fast trials (>10% trials <300ms) is part of the D1 algorithm

# add new column that records if RT < 300ms.
cleaned_df$too_fast_trial <- ifelse(cleaned_df$rt < .3, 1, 0) 

# calculate % acc and % fast trials from test block data
percentage_accuracy_and_fast_trials_df <- 
  group_by(cleaned_df, 
           participant) %>%
  filter(!is.na(test_block_pair)) %>%  # test blocks only
  dplyr::summarize(percentage_accuracy = round(sum(accuracy)/n(), 2),
            percent_fast_trials = sum(too_fast_trial)/n()) %>%  # arbitrary number of test block trials
  dplyr::mutate(exclude_based_on_fast_trials = ifelse(percent_fast_trials>=0.1, TRUE, FALSE)) %>%  
  select(participant,
         percentage_accuracy,
         exclude_based_on_fast_trials)

########################################################################
# Join data frames
output_df <- 
  join_all(list(demographics_df,
                n_pairs_practice_blocks_df,
                D1_df,
                D1_by_tt_df,
                D1_odd_df,
                D1_even_df,
                percentage_accuracy_and_fast_trials_df),
           by = "participant",
           type = "full")

########################################################################
# Write to file
write.csv(output_df, file = '~/git/Open Source IRAP/data processing/processed_IRAP_data.csv', row.names=FALSE)
