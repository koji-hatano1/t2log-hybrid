#!/bin/bash

# ===================================================================================================
#  SCRIPT:    t2log-hybrid.sh
#  METHOD:    Hatano Skull Stripping Method - Hybrid (v4.2)
#  STRATEGY:  Hybrid masking with T2w log-normal thresholding
#             and a T1w-derived SynthStrip brain mask
#  GITHUB:    https://github.com/koji-hatano1/t2log-hybrid
# ===================================================================================================

# --- Configuration ---
Subjlist="001 002 003"
BASE_PATH="/path/to/your/project"

# --- Extraction and threshold settings ---
BORDER_NUM=2
SD_FACTOR_T2=1.960

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
GLOBAL_LOG="hss-t2lh_v4.2_global_${TIMESTAMP}.log"

# --- Logging functions ---
log_info() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1"
    echo "$msg" | tee -a "$GLOBAL_LOG" "${SUBJ_LOG:-/dev/null}"
}

log_err() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] (Session ${SESSION}) $1"
    echo "$msg" | tee -a "$GLOBAL_LOG" "${SUBJ_LOG:-/dev/null}" "${SUBJ_ERR:-/dev/null}" >&2
}

log_info "=== Hatano Skull Stripping Method - Hybrid v4.2 Started ==="

for SESSION in ${Subjlist}; do

    SUBJ_LOG="${BASE_PATH}/hss-t2lh_v4.2_${SESSION}_${TIMESTAMP}.log"
    SUBJ_ERR="${BASE_PATH}/hss-t2lh_v4.2_${SESSION}_${TIMESTAMP}.err"

    log_info "-----------------------------------------------------------"
    log_info " Starting Session: ${SESSION}"

    T1wFolder="${BASE_PATH}/${SESSION}/T1w"
    AtlasSpaceFolder="${BASE_PATH}/${SESSION}/MNINonLinear"
    MASK="${T1wFolder}/T1w_acpc_brain_mask.nii.gz"

    if [ -f "${T1wFolder}/T2w_acpc_dc_restore.nii.gz" ] && \
       [ -f "${T1wFolder}/T1w_acpc_dc_restore.nii.gz" ]; then

        # ===========================================================================================
        # 1. T2w processing: SynthStrip + log-normal thresholding
        # ===========================================================================================

        log_info "  Step A: Creating T2w-based SynthStrip & Log-Normal Thresholding..."

        if mri_synthstrip \
            -i "${T1wFolder}/T2w_acpc_dc_restore.nii.gz" \
            -o "${T1wFolder}/T2w_tmp_brain.nii.gz" \
            -m "${T1wFolder}/T2w_tmp_mask.nii.gz" \
            -b "${BORDER_NUM}" \
            --no-csf >> "$SUBJ_LOG" 2>&1; then

            INPUT_BRAIN_T2="${T1wFolder}/T2w_tmp_brain.nii.gz"

            VOX_PRE_T2=$(fslstats "${INPUT_BRAIN_T2}" -V | awk '{print $1}')

            fslmaths "${INPUT_BRAIN_T2}" \
                -log \
                "${T1wFolder}/T2w_log_tmp.nii.gz"

            stats_log_t2=($(fslstats "${T1wFolder}/T2w_log_tmp.nii.gz" -M -S))
            M_L_T2=${stats_log_t2[0]}
            S_L_T2=${stats_log_t2[1]}

            AUTO_MIN_T2=$(echo "scale=10; e($M_L_T2 - ($SD_FACTOR_T2 * $S_L_T2))" | bc -l)
            AUTO_MAX_T2=$(echo "scale=10; e($M_L_T2 + ($SD_FACTOR_T2 * $S_L_T2))" | bc -l)

            VOX_THR_T2=$(fslstats "${INPUT_BRAIN_T2}" \
                -l "$AUTO_MIN_T2" \
                -u "$AUTO_MAX_T2" \
                -V | awk '{print $1}')

            DROP_PERCENT_T2=$(echo \
                "scale=4; ($VOX_PRE_T2 - $VOX_THR_T2) * 100 / $VOX_PRE_T2" \
                | bc -l)

        else
            log_err "T2w SynthStrip failed."
            continue
        fi


        # ===========================================================================================
        # 2. T1w processing: SynthStrip brain mask only
        # ===========================================================================================

        log_info "  Step B: Creating T1w-based SynthStrip brain mask..."

        if mri_synthstrip \
            -i "${T1wFolder}/T1w_acpc_dc_restore.nii.gz" \
            -o "${T1wFolder}/T1w_tmp_brain.nii.gz" \
            -m "${T1wFolder}/T1w_tmp_mask.nii.gz" \
            -b "${BORDER_NUM}" \
            --no-csf >> "$SUBJ_LOG" 2>&1; then

            T1_SYNTH_MASK="${T1wFolder}/T1w_tmp_mask.nii.gz"
            VOX_T1_MASK=$(fslstats "$T1_SYNTH_MASK" -V | awk '{print $1}')

        else
            log_err "T1w SynthStrip failed."
            continue
        fi


        # ===========================================================================================
        # 3. Backup original PreFS/HCP outputs
        # ===========================================================================================

        log_info "  Step B-2: Backing up original PreFS/HCP outputs..."

        if [ -f "$MASK" ]; then
            cp -n "$MASK" "${MASK%.nii.gz}_bet.nii.gz"
        fi

        for img in \
            T1w_acpc_dc_restore \
            T1w_acpc_dc \
            T1w_acpc \
            T2w_acpc_dc_restore \
            T2w_acpc; do

            target_img="${T1wFolder}/${img}_brain.nii.gz"

            if [ -f "$target_img" ]; then
                cp -n "$target_img" "${target_img%.nii.gz}_bet.nii.gz"
            fi
        done

        for img in T1w_restore T2w_restore; do

            target_img="${AtlasSpaceFolder}/${img}_brain.nii.gz"

            if [ -f "$target_img" ]; then
                cp -n "$target_img" "${target_img%.nii.gz}_bet.nii.gz"
            fi
        done


        # ===========================================================================================
        # 4. Build hybrid mask
        #
        # Outside AC safe zone:
        #     T1 SynthStrip mask ∩ T2 thresholded mask
        #
        # Inside AC safe zone:
        #     T1 SynthStrip mask only
        # ===========================================================================================

        log_info "  Step C: Building hybrid mask with AC-referenced T1w protection..."

        T2_THR_MASK="${T1wFolder}/T2w_tmp_thr_mask.nii.gz"
        AC_SAFE_ZONE="${T1wFolder}/AC_Safe_Zone_tmp.nii.gz"
        T2_PROTECTED_MASK="${T1wFolder}/T2w_AC_protected_tmp.nii.gz"
        FINAL_TMP_MASK="${T1wFolder}/final_tmp_mask.nii.gz"

        # Refined T2w mask
        fslmaths "${INPUT_BRAIN_T2}" \
            -thr "$AUTO_MIN_T2" \
            -uthr "$AUTO_MAX_T2" \
            -bin \
            -fillh \
            "$T2_THR_MASK"

        # -------------------------------------------------------------------------------------------
        # AC-referenced inferior-anterior switching region
        # -------------------------------------------------------------------------------------------

        AC_VOX=($(std2imgcoord \
            -vox \
            -std "$T2_THR_MASK" \
            -img "$T2_THR_MASK" <<< "0 0 0"))

        AC_X=${AC_VOX[0]}
        AC_Y=${AC_VOX[1]}
        AC_Z=${AC_VOX[2]}

        DIM_X=$(fslval "$T2_THR_MASK" dim1)
        DIM_Y=$(fslval "$T2_THR_MASK" dim2)
        DIM_Z=$(fslval "$T2_THR_MASK" dim3)

        SIZE_Y=$(echo "$DIM_Y - $AC_Y" | bc)

        # Full left-right extent,
        # anterior to AC and inferior to AC
        fslmaths "$T2_THR_MASK" \
            -mul 0 \
            -add 1 \
            -roi 0 "$DIM_X" "$AC_Y" "$SIZE_Y" 0 "$AC_Z" 0 1 \
            "$AC_SAFE_ZONE"

        # -------------------------------------------------------------------------------------------
        # T2 mask outside zone, unrestricted inside zone
        # -------------------------------------------------------------------------------------------

        fslmaths "$T2_THR_MASK" \
            -add "$AC_SAFE_ZONE" \
            -bin \
            "$T2_PROTECTED_MASK"

        # -------------------------------------------------------------------------------------------
        # Final hybrid:
        #
        # Outside zone:
        #     T1 SynthStrip ∩ T2 refined
        #
        # Inside zone:
        #     T1 SynthStrip only
        # -------------------------------------------------------------------------------------------

        fslmaths "$T1_SYNTH_MASK" \
            -mul "$T2_PROTECTED_MASK" \
            -bin \
            "$FINAL_TMP_MASK"

        # Final morphological cleanup
        fslmaths "$FINAL_TMP_MASK" \
            -ero \
            -dilM \
            "$MASK"


        # ===========================================================================================
        # 5. Statistics output
        # ===========================================================================================

        {
            echo "---------------------------------------------------------"
            echo "========= Hybrid Masking Results - v4.2 ================="
            echo "Session: ${SESSION}"

            VOX_DROP_T2=$(echo "$VOX_PRE_T2 - $VOX_THR_T2" | bc)
            VOX_REM_T2=$VOX_THR_T2

            echo " [T2w Log Thresholding]"
            echo "   Factor: ${SD_FACTOR_T2}SD"
            printf "   Thresholds: %.2f - %.2f\n" \
                "$AUTO_MIN_T2" "$AUTO_MAX_T2"
            printf "   Voxels    : Initial: %d | Dropped: %d (%.2f%%)\n" \
                "$VOX_PRE_T2" \
                "$VOX_DROP_T2" \
                "$DROP_PERCENT_T2"
            printf "               Remaining: %d\n" "$VOX_REM_T2"

            echo ""
            echo " [T1w SynthStrip]"
            printf "   Brain mask: %d voxels\n" "$VOX_T1_MASK"

            VOX_POST=$(fslstats "$MASK" -V | awk '{print $1}')

            echo ""
            echo " [Final Result]"
            echo "   Hybrid Mask Size: $VOX_POST voxels"
            echo "   Outside AC zone: T1 SynthStrip mask AND refined T2w mask"
            echo "   Inside AC zone : T1 SynthStrip mask only"
            echo "   Final cleanup  : ero + dilM"
            echo "---------------------------------------------------------"

        } | tee -a "$SUBJ_LOG" "$GLOBAL_LOG"


        # ===========================================================================================
        # 6. T2w visual histogram
        # ===========================================================================================

        {
            echo ""
            echo "--- T2w Visual Histogram (x: Out | o: In) ---"

            fslstats "${INPUT_BRAIN_T2}" \
                -l 0.0001 \
                -H 40 0 1000 | \
            awk \
                -v low="$AUTO_MIN_T2" \
                -v high="$AUTO_MAX_T2" \
                '{
                    val=NR*25;
                    line=sprintf("%5.0f: ", val);
                    mark=(val>high||val<low)?"x":"o";
                    content="";
                    for(i=0;i<$1/5000;i++){
                        content=content mark
                    }
                    print line content "|" $1
                }' | \
            tac | \
            awk -F'|' \
                'found||$2>0{
                    found=1;
                    print $1
                }' | \
            tac

            echo ""

        } >> "$SUBJ_LOG"


        # ===========================================================================================
        # 7. Update standard PreFS brain-extracted images in T1w folder
        # ===========================================================================================

        log_info "  Step D: Updating brain-extracted files in T1w folder..."

        for img in \
            T1w_acpc_dc_restore \
            T1w_acpc_dc \
            T1w_acpc \
            T2w_acpc_dc_restore \
            T2w_acpc; do

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


    # ===============================================================================================
    # 8. Synchronize to MNI space
    # ===============================================================================================

    log_info "  Step E: Synchronizing to MNI space..."

    if applywarp \
        --rel \
        --interp=nn \
        -i "$MASK" \
        -r "${AtlasSpaceFolder}/T1w_restore.nii.gz" \
        -w "${AtlasSpaceFolder}/xfms/acpc_dc2standard.nii.gz" \
        -o "${AtlasSpaceFolder}/tmp_m.nii.gz" \
        >> "$SUBJ_LOG" 2>&1; then

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


    # ===============================================================================================
    # 9. Cleanup temporary files
    # ===============================================================================================

    if [ "$KEEP_TMP" -eq 0 ]; then

        rm -f \
            "${T1wFolder}/T2w_tmp_brain.nii.gz" \
            "${T1wFolder}/T2w_tmp_mask.nii.gz" \
            "${T1wFolder}/T2w_log_tmp.nii.gz" \
            "${T1wFolder}/T1w_tmp_brain.nii.gz" \
            "${T1wFolder}/T1w_tmp_mask.nii.gz" \
            "${T1wFolder}/T2w_tmp_thr_mask.nii.gz" \
            "${T1wFolder}/AC_Safe_Zone_tmp.nii.gz" \
            "${T1wFolder}/T2w_AC_protected_tmp.nii.gz" \
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
# Auto-Summary Generator
# ===================================================================================================

SUMMARY_FILE="hss_t2lh_summary_${TIMESTAMP}.csv"

echo "Session,T2_SD,T2_Min,T2_Max,T2_Init,T2_Drop,T2_Drop%,T2_Rem,T1_SynthStrip,Final_Mask" \
    > "$SUMMARY_FILE"

for SESSION in ${Subjlist}; do

    block=$(sed -n \
        "/.*Starting Session: ${SESSION}/,/.*Finished Session: ${SESSION}/p" \
        "$GLOBAL_LOG")

    t2_sd=$(echo "$block" \
        | grep "Factor:" \
        | awk -F'Factor: ' '{print $2}' \
        | awk '{print $1}' \
        | sed 's/SD//' \
        | head -n 1)

    t2_min=$(echo "$block" \
        | grep "Thresholds:" \
        | awk '{print $2}' \
        | head -n 1)

    t2_max=$(echo "$block" \
        | grep "Thresholds:" \
        | awk '{print $4}' \
        | head -n 1)

    t2_init=$(echo "$block" \
        | grep "Initial:" \
        | awk -F'Initial: ' '{print $2}' \
        | awk '{print $1}' \
        | head -n 1)

    t2_drop=$(echo "$block" \
        | grep "Dropped:" \
        | awk -F'Dropped: ' '{print $2}' \
        | awk '{print $1}' \
        | head -n 1)

    t2_per=$(echo "$block" \
        | grep "Dropped:" \
        | awk -F'(' '{print $2}' \
        | awk -F'%' '{print $1}' \
        | head -n 1)

    t2_rem=$(echo "$block" \
        | grep "Remaining:" \
        | awk -F'Remaining: ' '{print $2}' \
        | head -n 1)

    t1_mask=$(echo "$block" \
        | grep "Brain mask:" \
        | awk '{print $3}' \
        | head -n 1)

    f_vox=$(echo "$block" \
        | grep "Hybrid Mask Size" \
        | awk '{print $4}' \
        | head -n 1)

    echo \
        "${SESSION},${t2_sd},${t2_min},${t2_max},${t2_init},${t2_drop},${t2_per},${t2_rem},${t1_mask},${f_vox}" \
        >> "$SUMMARY_FILE"

done

log_info "---------------------------------------------------------------"
log_info " [HSS Summary CSV Created] --> ${SUMMARY_FILE}"
log_info "---------------------------------------------------------------"
log_info "t2log-hybrid.sh: Hatano Skull Stripping Method v4.2 Complete."
