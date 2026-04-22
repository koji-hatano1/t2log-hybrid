# t2log-hybrid

This tool provides robust brain extraction using a hybrid extension of FreeSurfer’s `mri_synthstrip`, combining log-transformed T2w and squared T1w with spatially constrained statistical thresholding.

It improves mask stability in susceptibility-prone regions (e.g., orbitofrontal cortex) by selectively integrating T1w information where T2w signal is unreliable.

---

## Overview

While `mri_synthstrip` performs well across modalities, T2-weighted images may exhibit instability due to intensity inhomogeneity, flow voids, and susceptibility-related signal dropout.

**t2log-hybrid** extends t2log-strip by introducing spatially constrained integration of T1w information, enabling more stable masking in artifact-prone regions.

---

## Key Concept

- T2w (log-transformed): primary contrast for masking
- T1w (squared): selectively integrated in artifact-prone regions
- Spatial constraint: limits T1w substitution to anterior–ventral regions
- Statistical thresholding: determines mask boundaries independently for T2w and T1w

---

## Optimization Workflow

Parameters should be adjusted based on the histogram provided in each subject log.

### 1. Initial border_num Selection

- border_num=2: recommended default (conservative)
- border_num=1: tighter extraction (use if needed)

---

### 2. Fine-tuning via ci_threshold_t2 and ci_threshold_t1

Use the histogram in each subject log to adjust thresholding separately for T2w and T1w components.

- Initial setting:
  ci_threshold_t2=1.960, ci_threshold_t1=1.960

- If brain tissue is over-stripped:
  increase the corresponding threshold (e.g., 2.241 or 2.576)

- If non-brain tissue remains:
  decrease the threshold toward 1.960

Recommended reference values:

- 1.960 (95%)
- 2.241 (97.5%)
- 2.576 (99%)

Tip: Prioritize avoiding over-stripping.

---

## Usage

### 1. Setup

Edit the configuration in t2log-hybrid.sh:

    Subjlist="001 002 003"
    BASE_PATH="/path/to/your/project"
    border_num=2
    ci_threshold_t2=1.960
    ci_threshold_t1=1.960

---

### 2. Execution

    chmod +x t2log-hybrid.sh
    ./t2log-hybrid.sh

---

### 3. Review and Adjust

After execution:

1. Check histogram in $SUBJ_LOG
2. Evaluate mask quality
3. Adjust parameters if needed
4. Re-run until optimal

- If over-stripped: increase thresholds or use border_num=2
- If under-stripped: decrease thresholds or use border_num=1

---

## Recovery

    chmod +x recover_t2ls.sh
    ./recover_t2ls.sh

- Restores original files from _bet.nii.gz
- Recommended before re-running

---

## HCP Integration

- Updates T1w and T2w brain images
- Synchronizes masks to MNINonLinear space
- Applies transforms automatically
- Creates backups before modification

---

## QA & Reporting

A summary CSV (hss_t2ls_summary_*.csv) is generated:

- intensity thresholds
- SD factors
- voxel drop rates

---

## Viewer

    ./fview_t2ls.sh [Subject_ID]

---

## Prerequisites

- FSL 6.0.7
- FreeSurfer 7.4.1 (mri_synthstrip)
- bc
