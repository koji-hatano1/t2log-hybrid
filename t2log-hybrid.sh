#!/bin/bash

# ===================================================================================================
#  SCRIPT:    t2log-hybrid.sh
#  METHOD:    Hatano Skull Stripping Method - Hybrid (v4.11)
#  STRATEGY:  Hybrid SynthStrip Mask via T2w-based Log-Normal Thresholding
#             and T1w-based Squared-Space Thresholding for Ventral Refinement
#  GITHUB:    https://github.com/koji-hatano1/t2log-hybrid
# ===================================================================================================

# --- Configuration ---
Subjlist="001 002 003"
BASE_PATH="/path/to/your/project"

# --- Extraction and threshold settings ---
BORDER_NUM=2
SD_FACTOR_T2=1.960
SD_FACTOR_T1=1.960

# Reference:
# 1.960 (95%)    : standard
# 2.241 (97.5%)  : intermediate
# 2.576 (99%)    : conservative

# --- Temporary file handling ---
# 0: remove temporary files after each session
# 1: keep temporary files for debugging and visual inspection
KEEP_TMP=0

# --- Global logging ---
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
GLOBAL_LOG="hss-t2lh_v4.11_global_${TIMESTAMP}.log"

# --- Logging functions ---
log_info() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1"
    echo "$msg" | tee -a "$GLOBAL_LOG" "${SUBJ_LOG:-/dev/null}"
}

log_err() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] (Session ${SESSION}) $1"
    echo "$msg" | tee -a "$GLOBAL_LOG" "${SUBJ_LOG:-/dev/null}" "${SUBJ_ERR:-/dev/null}" >&2
}

log_info "=== Hatano Skull Stripping Method - Hybrid v4.11 Started ==="

for SESSION in ${Subjlist}; do
    SUBJ_LOG="${BASE_PATH}/hss-t2lh_v4.11_${SESSION}_${TIMESTAMP}.log"
    SUBJ_ERR="${BASE_PATH}/hss-t2lh_v4.11_${SESSION}_${TIMESTAMP}.err"

    log_info "-----------------------------------------------------------"
    log_info " Starting Session: ${SESSION}"

    T1wFolder="${BASE_PATH}/${SESSION}/T1w"
    AtlasSpaceFolder="${BASE_PATH}/${SESSION}/MNINonLinear"
    MASK="${T1wFolder}/T1w_acpc_brain_mask.nii.gz"

    if [ -f "${T1wFolder}/T2w_acpc_dc_restore.nii.gz" ] && \
       [ -f "${T1wFolder}/T1w_acpc_dc_restore.nii.gz" ]; then

        log_info "  Step A: Creating T2w-based SynthStrip & Log-Normal Thresholding..."

        # --- 1. T2w processing: SynthStrip + log-normal thresholding ---
        if mri_synthstrip \
            -i "${T1wFolder}/T2w_acpc_dc_restore.nii.gz" \
            -o "${T1wFolder}/T2w_tmp_brain.nii.gz" \
            -m "${T1wFolder}/T2w_tmp_mask.nii.gz" \
            -b "${BORDER_NUM}" \
            --no-csf >> "$SUBJ_LOG" 2>&1; then

            INPUT_BRAIN_T2="${T1wFolder}/T2w_tmp_brain.nii.gz"
            VOX_PRE_T2=$(fslstats "${INPUT_BRAIN_T2}" -V | awk '{print $1}')

            fslmaths "${INPUT_BRAIN_T2}" -log "${T1wFolder}/T2w_log_tmp.nii.gz"

            stats_log_t2=($(fslstats "${T1wFolder}/T2w_log_tmp.nii.gz" -M -S))
            M_L_T2=${stats_log_t2[0]}
            S_L_T2=${stats_log_t2[1]}

            AUTO_MIN_T2=$(echo "scale=10; e($M_L_T2 - ($SD_FACTOR_T2 * $S_L_T2))" | bc -l)
            AUTO_MAX_T2=$(echo "scale=10; e($M_L_T2 + ($SD_FACTOR_T2 * $S_L_T2))" | bc -l)

            VOX_THR_T2=$(fslstats "${INPUT_BRAIN_T2}" -l "$AUTO_MIN_T2" -u "$AUTO_MAX_T2" -V | awk '{print $1}')
            DROP_PERCENT_T2=$(echo "scale=4; ($VOX_PRE_T2 - $VOX_THR_T2) * 100 / $VOX_PRE_T2" | bc -l)
        else
            log_err "T2w SynthStrip failed."
            continue
        fi

        log_info "  Step B: Creating T1w-based SynthStrip & Squared Space Thresholding..."

        # --- 2. T1w processing: SynthStrip + squared-space thresholding ---
        if mri_synthstrip \
            -i "${T1wFolder}/T1w_acpc_dc_restore.nii.gz" \
            -o "${T1wFolder}/T1w_tmp_brain.nii.gz" \
            -m "${T1wFolder}/T1w_tmp_mask.nii.gz" \
            -b "${BORDER_NUM}" \
            --no-csf >> "$SUBJ_LOG" 2>&1; then

            INPUT_BRAIN_T1="${T1wFolder}/T1w_tmp_brain.nii.gz"
            VOX_PRE_T1=$(fslstats "${INPUT_BRAIN_T1}" -V | awk '{print $1}')

            fslmaths "${INPUT_BRAIN_T1}" -sqr "${T1wFolder}/T1w_sqr_tmp.nii.gz"

            stats_sqr_t1=($(fslstats "${T1wFolder}/T1w_sqr_tmp.nii.gz" -M -S))
            M_S_T1=${stats_sqr_t1[0]}
            S_S_T1=${stats_sqr_t1[1]}

            AUTO_MIN_VAL=$(echo "scale=10; $M_S_T1 - ($SD_FACTOR_T1 * $S_S_T1)" | bc -l)
            AUTO_MAX_VAL=$(echo "scale=10; $M_S_T1 + ($SD_FACTOR_T1 * $S_S_T1)" | bc -l)

            if (( $(echo "$AUTO_MIN_VAL < 0" | bc -l) )); then
                AUTO_MIN_VAL=0
            fi

            AUTO_MIN_T1=$(echo "scale=10; sqrt($AUTO_MIN_VAL)" | bc -l)
            AUTO_MAX_T1=$(echo "scale=10; sqrt($AUTO_MAX_VAL)" | bc -l)

            VOX_THR_T1=$(fslstats "${INPUT_BRAIN_T1}" -l "$AUTO_MIN_T1" -u "$AUTO_MAX_T1" -V | awk '{print $1}')
            DROP_PERCENT_T1=$(echo "scale=4; ($VOX_PRE_T1 - $VOX_THR_T1) * 100 / $VOX_PRE_T1" | bc -l)
        else
            log_err "T1w SynthStrip failed."
            continue
        fi

        # --- 3. Backup original PreFS/HCP outputs ---
        log_info "  Step B-2: Backing up original PreFS/HCP outputs..."

        # Backup the standard PreFS/HCP brain mask.
        if [ -f "$MASK" ]; then
            cp -n "$MASK" "${MASK%.nii.gz}_bet.nii.gz"
        fi

        # Backup standard PreFS brain-extracted images in the T1w folder.
        # This list follows t2log-strip and standard PreFS outputs.
        for img in T1w_acpc_dc_restore T1w_acpc_dc T1w_acpc T2w_acpc_dc_restore T2w_acpc; do
            target_img="${T1wFolder}/${img}_brain.nii.gz"
            if [ -f "$target_img" ]; then
                cp -n "$target_img" "${target_img%.nii.gz}_bet.nii.gz"
            fi
        done

        # Backup standard MNINonLinear brain-extracted images generated by PreFS.
        for img in T1w_restore T2w_restore; do
            target_img="${AtlasSpaceFolder}/${img}_brain.nii.gz"
            if [ -f "$target_img" ]; then
                cp -n "$target_img" "${target_img%.nii.gz}_bet.nii.gz"
            fi
        done

        # --- 4. Build hybrid mask and OFC rescue mask ---
        log_info "  Step C: Consolidating Mask with OFC Protection..."

        T2_THR_MASK="${T1wFolder}/T2w_tmp_thr_mask.nii.gz"
        T1_THR_MASK="${T1wFolder}/T1w_tmp_thr_mask.nii.gz"
        OFC_RESCUE_MASK="${T1wFolder}/T1w_acpc_brain_mask_OFC_safe.nii.gz"
        AC_SAFE_ZONE="${T1wFolder}/AC_Safe_Zone_tmp.nii.gz"
        FINAL_TMP_MASK="${T1wFolder}/final_tmp_mask.nii.gz"

        fslmaths "${INPUT_BRAIN_T2}" -thr "$AUTO_MIN_T2" -uthr "$AUTO_MAX_T2" -bin -fillh "$T2_THR_MASK"
        fslmaths "${INPUT_BRAIN_T1}" -thr "$AUTO_MIN_T1" -uthr "$AUTO_MAX_T1" -bin -fillh "$T1_THR_MASK"

        # OFC rescue: protect the anterior-inferior zone referenced to AC.
        AC_VOX=($(std2imgcoord -vox -std "$T2_THR_MASK" -img "$T2_THR_MASK" <<< "0 0 0"))
        AC_X=${AC_VOX[0]}
        AC_Y=${AC_VOX[1]}
        AC_Z=${AC_VOX[2]}

        DIM_X=$(fslval "$T2_THR_MASK" dim1)
        DIM_Y=$(fslval "$T2_THR_MASK" dim2)
        DIM_Z=$(fslval "$T2_THR_MASK" dim3)

        SIZE_Y=$(echo "$DIM_Y - $AC_Y" | bc)

        fslmaths "$T2_THR_MASK" -mul 0 -add 1 \
            -roi 0 "$DIM_X" "$AC_Y" "$SIZE_Y" 0 "$AC_Z" 0 1 \
            "$AC_SAFE_ZONE"

        fslmaths "$T2_THR_MASK" -add "$AC_SAFE_ZONE" -bin "$OFC_RESCUE_MASK"

        # Final merge: T1-thresholded mask constrained by the T2-protected OFC region.
        fslmaths "$T1_THR_MASK" -mul "$OFC_RESCUE_MASK" -bin "$FINAL_TMP_MASK"
        fslmaths "$FINAL_TMP_MASK" -ero -dilM "$MASK"

        # Write the final mask to the standard PreFS/HCP mask path.

        # --- 5. Statistics output ---
        {
            echo "---------------------------------------------------------"
            echo "====== Independent Non-linear Thresholding Results ======"
            echo "Session: ${SESSION}"

            VOX_DROP_T2=$(echo "$VOX_PRE_T2 - $VOX_THR_T2" | bc)
            VOX_REM_T2=$VOX_THR_T2

            echo " [T2w (Log)] Factor: ${SD_FACTOR_T2}SD"
            printf "   Thresholds: %.2f - %.2f\n" "$AUTO_MIN_T2" "$AUTO_MAX_T2"
            printf "   Voxels    : Initial: %d | Dropped: %d (%.2f%%)\n" "$VOX_PRE_T2" "$VOX_DROP_T2" "$DROP_PERCENT_T2"
            printf "               Remaining: %d\n" "$VOX_REM_T2"

            VOX_DROP_T1=$(echo "$VOX_PRE_T1 - $VOX_THR_T1" | bc)
            VOX_REM_T1=$VOX_THR_T1

            echo " [T1w (Sqr)] Factor: ${SD_FACTOR_T1}SD"
            printf "   Thresholds: %.2f - %.2f\n" "$AUTO_MIN_T1" "$AUTO_MAX_T1"
            printf "   Voxels    : Initial: %d | Dropped: %d (%.2f%%)\n" "$VOX_PRE_T1" "$VOX_DROP_T1" "$DROP_PERCENT_T1"
            printf "               Remaining: %d\n" "$VOX_REM_T1"

            RATIO_T1_T2=$(echo "scale=2; ($VOX_REM_T1 / $VOX_REM_T2) * 100" | bc)
            VOX_POST=$(fslstats "$MASK" -V | awk '{print $1}')

            echo " [Final Result]"
            echo "   T1w/T2w Ratio: ${RATIO_T1_T2}%"
            echo "   Hybrid Mask Size: $VOX_POST voxels"
            echo "   Steps: fillh (T1w/T2w individually)"
            echo "          -> ero+dilM (Hybrid mask: remove small islands)"
            echo "---------------------------------------------------------"
        } | tee -a "$SUBJ_LOG" "$GLOBAL_LOG"

        # --- 6. Dual visual histograms ---
        {
            echo ""
            echo "--- T2w Visual Histogram (x: Out | o: In) ---"
            fslstats "${INPUT_BRAIN_T2}" -l 0.0001 -H 40 0 1000 | \
            awk -v low="$AUTO_MIN_T2" -v high="$AUTO_MAX_T2" \
            '{val=NR*25; line=sprintf("%5.0f: ", val); mark=(val>high||val<low)?"x":"o"; content=""; \
            for(i=0;i<$1/5000;i++){content=content mark} print line content "|" $1}' | tac | \
            awk -F'|' 'found||$2>0{found=1; print $1}' | tac

            echo ""
            echo "--- T1w Visual Histogram (x: Out | o: In) ---"
            fslstats "${INPUT_BRAIN_T1}" -l 0.0001 -H 40 0 1000 | \
            awk -v low="$AUTO_MIN_T1" -v high="$AUTO_MAX_T1" \
            '{val=NR*25; line=sprintf("%5.0f: ", val); mark=(val>high||val<low)?"x":"o"; content=""; \
            for(i=0;i<$1/5000;i++){content=content mark} print line content "|" $1}' | tac | \
            awk -F'|' 'found||$2>0{found=1; print $1}' | tac

            echo ""
        } >> "$SUBJ_LOG"

        # --- 7. Update standard PreFS brain-extracted images in the T1w folder ---
        log_info "  Step D: Updating brain-extracted files in T1w folder..."

        for img in T1w_acpc_dc_restore T1w_acpc_dc T1w_acpc T2w_acpc_dc_restore T2w_acpc; do
            if [ -f "${T1wFolder}/${img}.nii.gz" ]; then
                fslmaths "${T1wFolder}/${img}.nii.gz" \
                    -mas "$MASK" \
                    "${T1wFolder}/${img}_brain.nii.gz"
            fi
        done

    else
        log_err "Required ACPC files missing."
        continue
    fi

    # --- 8. Synchronize to MNI space ---
    log_info "  Step E: Synchronizing to MNI space..."

    # Use a temporary MNI-space mask for restored brain-image updates.
    if applywarp --rel --interp=nn \
        -i "$MASK" \
        -r "${AtlasSpaceFolder}/T1w_restore.nii.gz" \
        -w "${AtlasSpaceFolder}/xfms/acpc_dc2standard.nii.gz" \
        -o "${AtlasSpaceFolder}/tmp_m.nii.gz" >> "$SUBJ_LOG" 2>&1; then

        for img in T1w_restore T2w_restore; do
            if [ -f "${AtlasSpaceFolder}/${img}.nii.gz" ]; then
                fslmaths "${AtlasSpaceFolder}/${img}.nii.gz" \
                    -mas "${AtlasSpaceFolder}/tmp_m.nii.gz" \
                    "${AtlasSpaceFolder}/${img}_brain.nii.gz"
            fi
        done

        rm -f "${AtlasSpaceFolder}/tmp_m.nii.gz"
        log_info "  [Done] MNI synchronization complete."
    else
        log_err "applywarp failed."
    fi

    # --- 9. Cleanup temporary files ---
    if [ "$KEEP_TMP" -eq 0 ]; then
        rm -f "${T1wFolder}/T2w_tmp_brain.nii.gz" \
              "${T1wFolder}/T2w_tmp_mask.nii.gz" \
              "${T1wFolder}/T2w_log_tmp.nii.gz" \
              "${T1wFolder}/T1w_tmp_brain.nii.gz" \
              "${T1wFolder}/T1w_tmp_mask.nii.gz" \
              "${T1wFolder}/T1w_sqr_tmp.nii.gz" \
              "${T1wFolder}/T2w_tmp_thr_mask.nii.gz" \
              "${T1wFolder}/T1w_tmp_thr_mask.nii.gz" \
              "${T1wFolder}/T1w_acpc_brain_mask_OFC_safe.nii.gz" \
              "${T1wFolder}/AC_Safe_Zone_tmp.nii.gz" \
              "${T1wFolder}/final_tmp_mask.nii.gz" \
              "${AtlasSpaceFolder}/tmp_m.nii.gz"

        log_info "  [Cleanup] Temporary files removed."
    else
        log_info "  [Cleanup] Temporary files kept for debugging."
    fi

    log_info " Finished Session: ${SESSION}"
done

unset SUBJ_LOG

# ===================================================================================================
#  Auto-Summary Generator
# ===================================================================================================

SUMMARY_FILE="hss_t2lh_summary_${TIMESTAMP}.csv"

echo "Session,T2_SD,T1_SD,T2_Min,T2_Max,T2_Init,T2_Drop,T2_Drop%,T2_Rem,T1_Min,T1_Max,T1_Init,T1_Drop,T1_Drop%,T1_Rem,T1T2_Ratio,Final_Mask" > "$SUMMARY_FILE"

for SESSION in ${Subjlist}; do
    block=$(sed -n "/.*Starting Session: ${SESSION}/,/.*Finished Session: ${SESSION}/p" "$GLOBAL_LOG")

    t2_sd=$(echo "$block" | grep "\[T2w" | awk -F'Factor: ' '{print $2}' | awk '{print $1}' | sed 's/SD//' | head -n 1)
    t2_min=$(echo "$block" | grep "\[T2w" -A 1 | grep "Thresholds" | awk '{print $2}' | head -n 1)
    t2_max=$(echo "$block" | grep "\[T2w" -A 1 | grep "Thresholds" | awk '{print $4}' | head -n 1)
    t2_init=$(echo "$block" | grep "\[T2w" -A 3 | grep "Initial:" | awk -F'Initial: ' '{print $2}' | awk '{print $1}' | head -n 1)
    t2_drop=$(echo "$block" | grep "\[T2w" -A 3 | grep "Dropped:" | awk -F'Dropped: ' '{print $2}' | awk '{print $1}' | head -n 1)
    t2_per=$(echo "$block" | grep "\[T2w" -A 3 | grep "Dropped:" | awk -F'(' '{print $2}' | awk -F'%' '{print $1}' | head -n 1)
    t2_rem=$(echo "$block" | grep "\[T2w" -A 3 | grep "Remaining:" | awk -F'Remaining: ' '{print $2}' | head -n 1)

    t1_sd=$(echo "$block" | grep "\[T1w" | awk -F'Factor: ' '{print $2}' | awk '{print $1}' | sed 's/SD//' | head -n 1)
    t1_min=$(echo "$block" | grep "\[T1w" -A 1 | grep "Thresholds" | awk '{print $2}' | head -n 1)
    t1_max=$(echo "$block" | grep "\[T1w" -A 1 | grep "Thresholds" | awk '{print $4}' | head -n 1)
    t1_init=$(echo "$block" | grep "\[T1w" -A 3 | grep "Initial:" | awk -F'Initial: ' '{print $2}' | awk '{print $1}' | head -n 1)
    t1_drop=$(echo "$block" | grep "\[T1w" -A 3 | grep "Dropped:" | awk -F'Dropped: ' '{print $2}' | awk '{print $1}' | head -n 1)
    t1_per=$(echo "$block" | grep "\[T1w" -A 3 | grep "Dropped:" | awk -F'(' '{print $2}' | awk -F'%' '{print $1}' | head -n 1)
    t1_rem=$(echo "$block" | grep "\[T1w" -A 3 | grep "Remaining:" | awk -F'Remaining: ' '{print $2}' | head -n 1)

    t1t2_ratio=$(echo "$block" | grep "T1w/T2w Ratio" | awk '{print $3}' | sed 's/%//' | head -n 1)
    f_vox=$(echo "$block" | grep "Hybrid Mask Size" | awk '{print $4}' | head -n 1)

    echo "${SESSION},${t2_sd},${t1_sd},${t2_min},${t2_max},${t2_init},${t2_drop},${t2_per},${t2_rem},${t1_min},${t1_max},${t1_init},${t1_drop},${t1_per},${t1_rem},${t1t2_ratio},${f_vox}" >> "$SUMMARY_FILE"
done

log_info "---------------------------------------------------------------"
log_info " [HSS Summary CSV Created] --> ${SUMMARY_FILE}"
log_info "---------------------------------------------------------------"
log_info "t2log-hybrid.sh: Hatano Skull Stripping Method v4.11 Complete."
