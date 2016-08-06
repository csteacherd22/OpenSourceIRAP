########################################################################
# Calculate D1 scores, accuracy and latency summary statistics 
########################################################################
# Author: 
# Ian Hussey (ian.hussey@ugent.be)

# Known issues:
# 

# Instructions:
# Simply set the input [line containing setwd()] and output 
# [line containing write.csv()] directories and run script.

# To do:
# 1. DIRAP produces some scores >2, which shouldn't be possible. check with manual calc.
# consolidate the latency summaries. the one in the dIRAP calc is neat, 
# but it lacks a fast trial excluder.
# 2. Accuracy summary calc hasn't been updated.
# internal consistency data needed.

########################################################################
# Clean workspace
rm(list=ls())

########################################################################
# Dependencies
library(plyr) #must import before dplyr
library(dplyr)
library(tidyr)
library(readr)
library(data.table)
library(lazyeval)

########################################################################
# Data acquisition and cleaning
setwd("~/git/IRAP/data")
files <- list.files(pattern = "\\.csv$")
input_df <- tbl_df(rbind.fill(lapply(files, fread, header=TRUE)))

# Make some variable names more transparent, plus rectify the the accuracy variable
cleaned_df <- 
  rename(input_df,
         trial_type = trialType,
         practice_block_pair = practice_blocks.thisRepN,
         test_block_pair = test_blocks.thisRepN,
         rt_a = required_response_A.rt,
         rt_b = required_response_B.rt,
         accuracy_a = feedback_response_A.corr,
         accuracy_b = feedback_response_B.corr,
         starting_block = StartingBlock,
         latency_criterion = latencyCriterion,
         accuracy_criterion = accuracyCriterion) %>%
  rowwise() %>%  # needed for the row-wise mutate() for rt and accuracy below 
  mutate(accuracy_a = abs(accuracy_a - 1),  # recitfies the direction of accuracy so that 0 = error and 1 = correct.
         accuracy_b = abs(accuracy_b - 1),
         practice_block_pair = practice_block_pair + 1,  # recifies block to start at 1
         test_block_pair = test_block_pair + 1,
         rt = sum(rt_a, rt_b, na.rm=TRUE),  # get all rts in one column 
         accuracy = sum(accuracy_a, accuracy_b, na.rm=TRUE)) %>%  # get all accuracies in one column
  ungroup() %>%  # removes rowwise
  select(participant,
         starting_block,
         practice_block_pair,
         test_block_pair,
         trial_type,
         rt_a,
         rt_b,
         rt,
         accuracy_a,
         accuracy_b,
         accuracy_criterion,
         latency_criterion,
         age,
         gender,
         date,
         max_pairs_practice_blocks,
         moving_response_options,
         n_pairs_test_blocks)

########################################################################
# demographics and parameter data
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
         moving_response_options)

########################################################################
# D-IRAP scores and latency summaries

# D-IRAP calculated from all test blocks at once
D_IRAP_df <-  
  group_by(cleaned_df, 
           participant) %>%
  filter(rt <= 10000) %>%  # SAMPLE DATA IS PRAC BLOCKS ONLY
  #filter(rt <= 10000 &
  #         !is.na(test_block_pair)) %>%  # test blocks only
  summarize(rt_a_mean = round(mean(rt_a, na.rm = TRUE), 2),
            rt_b_mean = round(mean(rt_b, na.rm = TRUE), 2),
            rt_mean = round(mean(rt), 2),
            rt_sd = sd(rt)) %>%
  mutate(diff = rt_b_mean - rt_a_mean,
         D_IRAP = round(diff / rt_sd, 2)) %>%  # D_IRAP refers calculated from all test blocks at once.
  select(participant, 
         rt_a_mean,
         rt_b_mean,
         rt_mean,
         D_IRAP)

# D-IRAP calculated for each trial type, calculated from all test blocks at once
D_IRAP_by_tt_df <-  
  group_by(cleaned_df, 
           participant,
           trial_type) %>%
  filter(rt <= 10000) %>%  # SAMPLE DATA IS PRAC BLOCKS ONLY
  #filter(rt <= 10000 &
  #         !is.na(test_block_pair)) %>%  # test blocks only
  summarize(rt_a_mean = round(mean(rt_a, na.rm = TRUE), 2),
            rt_b_mean = round(mean(rt_b, na.rm = TRUE), 2),
            rt_mean = round(mean(rt), 2),
            rt_sd = sd(rt)) %>%
  mutate(diff = rt_b_mean - rt_a_mean,
         D_IRAP_by_tt = round(diff / rt_sd, 2)) %>%  # D_IRAP refers calculated from all test blocks at once.
  select(participant, 
         trial_type,
         D_IRAP_by_tt) %>%
  spread(trial_type, D_IRAP_by_tt) %>%
  rename(D_IRAP_trial_type_1 = `1`,
         D_IRAP_trial_type_2 = `2`,
         D_IRAP_trial_type_3 = `3`,
         D_IRAP_trial_type_4 = `4`)

########################################################################
# Accuracy and latency stats 
######## Needs changing becasue of variable block lengths!
accuracy_summary_df <- 
  group_by(df, participant) %>%
  summarize(critical_blocks_percentage_accuracy = round(sum(accuracy[block == 3 |
                                                                    block == 4 | 
                                                                    block == 6 | 
                                                                    block == 7]) / 120, 2)) # 120 critical trials in the IAT

df$fast_trial <- ifelse(df$rt < .3, 1, 0)  # add new column that records if RT < 300. Should probably be done using mutate() for code consistency, but this works fine.

latency_summary_df <-
  group_by(df, participant) %>%
  filter(block == 3 | block == 4 | block == 6 | block == 7) %>%
  summarize(critical_blocks_mean_rt = round(mean(rt), 2), 
            percent_fast_trials = sum(fast_trial)/120) %>%  # 120 critical trials
  mutate(exclude_based_on_fast_trials = ifelse(percent_fast_trials>=0.1, TRUE, FALSE)) %>%  # exclusions based on too many fast trials is part of the D1 algorithm
  select(participant,
         critical_blocks_mean_rt,
         exclude_based_on_fast_trials)

########################################################################
# Prac block data

# calc number of prac blocks completed. 
# DIRAP data too?

########################################################################
# Join data frames
all_tasks_df <- 
  join_all(list(demographics_df,
                accuracy_summary_df,
                latency_summary_df,
                D_IRAP_df,
                D_IRAP_by_tt_df),
           by = "participant",
           type = "full")

########################################################################
# Write to file
write.csv(all_tasks_df, file = '~/git/IRAP/data processing/IRAP_data.csv', row.names=FALSE)
