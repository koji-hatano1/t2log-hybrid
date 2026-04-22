#!/bin/bash

# --- Configuration ---
# Set the path to your HCP study directory below.
BASE_PATH="/path/to/your/project"

# --- Argument Check ---
if [ $# -lt 1 ]; then
    echo "Usage: fview_t2lh.sh [Subject ID]"
    echo "Example: fview_t2lh.sh 001"
    exit 1
fi

SUBJ=$1
T1wFolder="${BASE_PATH}/${SUBJ}/T1w"

# --- File Existence Check ---
if [ ! -f "${T1wFolder}/T1w_acpc_dc_restore.nii.gz" ] || [ ! -f "${T1wFolder}/T2w_acpc_dc_restore.nii.gz" ]; then
    echo "Error: Required T1w or T2w files for ${SUBJ} are missing."
    exit 1
fi

echo "--- Launching Freeview: Session ${SUBJ} ---"
echo "Layer 1 (Bottom): T2w_acpc_dc_restore (Gray, Opacity: 1.0)"
echo "Layer 2         : T1w_acpc_dc_restore (Gray, Opacity: 1.0)"
echo "Layer 3 (Middle): Original BET (_bet) [Colormap: Heat, Opacity: 1.0]"
echo "Layer 4 (Top)   : t2log-strip Mask [Colormap: Jet, Opacity: 0.5]"

# --- Freeview Execution Command ---
freeview -v \
  "${T1wFolder}/T2w_acpc_dc_restore.nii.gz" \
  "${T1wFolder}/T1w_acpc_dc_restore.nii.gz" \
  "${T1wFolder}/T1w_acpc_dc_restore_brain_bet.nii.gz:colormap=heat:opacity=1.0" \
  "${T1wFolder}/T1w_acpc_dc_restore_brain.nii.gz:colormap=jet:opacity=0.5" &
