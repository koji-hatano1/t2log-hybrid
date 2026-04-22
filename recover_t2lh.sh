#!/bin/bash

# ===================================================================================================
#  SCRIPT:    recover_t2lh.sh (Universal Recovery)
#  PROJECT:   Hatano Skull Stripping Method (Hybrid & T2w)
#  STRATEGY:  Full Undo - Restore *_bet.nii.gz & Cleanup Intermediate Artifacts
# ===================================================================================================

# --- Configuration ---
Subjlist="001 002 003"
BASE_PATH="/path/to/your/project"

TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
LOG_FILE="recovery_hss_${TIMESTAMP}.log"

# Function to output to both terminal and log file
log_info() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1" | tee -a "$LOG_FILE"; }

log_info "=== Hatano Skull Stripping: Recovery Process Started ==="

for SESSION in ${Subjlist} ; do
    log_info "------------------------------------------------------------"
    log_info " Restoring Session: ${SESSION}"
    
    T1wFolder="${BASE_PATH}/${SESSION}/T1w"
    AtlasSpaceFolder="${BASE_PATH}/${SESSION}/MNINonLinear"

    # --- 1. Restore Mask Files ---
    # Restores original T1w_acpc_brain_mask and brainmask_fs
    for m in "T1w_acpc_brain_mask" "brainmask_fs"; do
        if [ -f "${T1wFolder}/${m}_bet.nii.gz" ]; then
            log_info "  Restoring ${m}.nii.gz from *_bet backup..."
            rm -f "${T1wFolder}/${m}.nii.gz"
            mv -f "${T1wFolder}/${m}_bet.nii.gz" "${T1wFolder}/${m}.nii.gz"
        fi
    done

    # --- 2. Restore Brain-Extracted Images (ACPC Space) ---
    log_info "  Restoring original _brain.nii.gz files in T1w folder..."
    for img in T1w_acpc_dc_restore T1w_acpc_dc T1w_acpc T2w_acpc_dc_restore T2w_acpc_dc T2w_acpc; do
        if [ -f "${T1wFolder}/${img}_brain_bet.nii.gz" ]; then
            rm -f "${T1wFolder}/${img}_brain.nii.gz"
            mv -f "${T1wFolder}/${img}_brain_bet.nii.gz" "${T1wFolder}/${img}_brain.nii.gz"
        fi
    done

    # --- 3. Restore Atlas Files (MNI Space) ---
    log_info "  Restoring Atlas files in MNINonLinear folder..."
    # Restore MNI brainmask
    if [ -f "${AtlasSpaceFolder}/brainmask_fs_bet.nii.gz" ]; then
        rm -f "${AtlasSpaceFolder}/brainmask_fs.nii.gz"
        mv -f "${AtlasSpaceFolder}/brainmask_fs_bet.nii.gz" "${AtlasSpaceFolder}/brainmask_fs.nii.gz"
    fi
    # Restore MNI brain-extracted images
    for img in T1w_restore T1w T2w_restore T2w; do
        if [ -f "${AtlasSpaceFolder}/${img}_brain_bet.nii.gz" ]; then
            rm -f "${AtlasSpaceFolder}/${img}_brain.nii.gz"
            mv -f "${AtlasSpaceFolder}/${img}_brain_bet.nii.gz" "${AtlasSpaceFolder}/${img}_brain.nii.gz"
        fi
    done

    # --- 4. Deep Cleanup of Intermediate Files (Hybrid & T2w Artifacts) ---
    log_info "  Cleaning up all intermediate artifacts..."
    # SynthStrip & Thresholding results
    rm -f "${T1wFolder}"/T1w_tmp_*.nii.gz
    rm -f "${T1wFolder}"/T2w_tmp_*.nii.gz
    rm -f "${T1wFolder}"/T1w_sqr_tmp.nii.gz
    rm -f "${T1wFolder}"/T2w_log_tmp.nii.gz
    # OFC Rescue & Final Merge artifacts
    rm -f "${T1wFolder}/AC_Safe_Zone_tmp.nii.gz"
    rm -f "${T1wFolder}/T1w_acpc_brain_mask_OFC_safe.nii.gz"
    rm -f "${T1wFolder}/final_tmp_mask.nii.gz"

    log_info " Finished Recovery for Session: ${SESSION}"
done

log_info "------------------------------------------------------------"
log_info " Recovery Complete. All files restored to pre-HSS state."
log_info "------------------------------------------------------------"
