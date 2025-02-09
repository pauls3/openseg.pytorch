#!/usr/bin/env bash
SCRIPTPATH="$( cd "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
cd $SCRIPTPATH
cd ../../
. config.profile
# check the enviroment info
nvidia-smi
# ${PYTHON} -m pip3 install yacs

export PYTHONPATH="$PWD":$PYTHONPATH

DATA_DIR="${DATA_ROOT}/RailSem19/custom_split"
SAVE_DIR="_out/seg_result/rs19/"
BACKBONE="hrnet48"
CONFIGS="configs/rs19/H_48_D_4.json"
CONFIGS_TEST="configs/rs19/H_48_D_4_TEST.json"

MAX_ITERS=20000
BATCH_SIZE=24

MODEL_NAME="hrnet_w48_ocr_b"
LOSS_TYPE="fs_auxohemce_loss"
CHECKPOINTS_NAME="${MODEL_NAME}_${BACKBONE}_${BATCH_SIZE}_${MAX_ITERS}_trainval_coarse_trainval_mapillary_pretrain_freeze_bn_"$2
LOG_FILE="./log/rs19/${CHECKPOINTS_NAME}.log"
echo "Logging to $LOG_FILE"
mkdir -p `dirname $LOG_FILE`

# PRETRAINED_MODEL="./pretrained_model/hrnet_w48_ocr_b_mapillary_bs16_500000_1024x1024_lr0.01_1_latest.pth"
# PRETRAINED_MODEL="./checkpoints/cityscapes/hrnet_w48_ocr_b_hrnet48__8_120000_trainval_ohem_mapillary_miou_508_1_latest.pth" # miou=83.63 on test.

# PRETRAINED_MODEL="./checkpoints/cityscapes/hrnet_w48_ocr_b_hrnet48_8_20000_trainval_coarse_trainval_mapillary_pretrain_freeze_bn_1_latest.pth"
PRETRAINED_MODEL="./checkpoints/rs19/best/hrnet_w48_ocr_b_hrnet48_24_20000_trainval_coarse_trainval_mapillary_pretrain_freeze_bn_1_max_performance.pth"

if [ "$1"x == "train"x ]; then
  ${PYTHON} -u main.py --configs ${CONFIGS} \
                       --drop_last y \
                       --train_batch_size ${BATCH_SIZE} \
                       --include_val y  \
                       --phase train --gathered n --loss_balance y --log_to_file n \
                       --backbone ${BACKBONE} --model_name ${MODEL_NAME} --gpu 0 1 2 3 \
                       --data_dir ${DATA_DIR} --loss_type ${LOSS_TYPE} --max_iters ${MAX_ITERS} \
                       --resume ${PRETRAINED_MODEL} \
                       --resume_strict False \
                       --resume_eval_train False \
                       --resume_eval_val False \
                       --checkpoints_name ${CHECKPOINTS_NAME} \
                       --base_lr 0.0002 \
                       --test_interval 2000 \
                       2>&1 | tee ${LOG_FILE}


elif [ "$1"x == "resume"x ]; then
  ${PYTHON} -u main.py --configs ${CONFIGS} --drop_last y --train_batch_size ${BATCH_SIZE} --include_val y \
                       --phase train --gathered n --loss_balance y --log_to_file n \
                       --backbone ${BACKBONE} --model_name ${MODEL_NAME} --max_iters ${MAX_ITERS} \
                       --data_dir ${DATA_DIR} --loss_type ${LOSS_TYPE} --gpu 0 1 2 3 \
                       --resume_continue y --resume ./checkpoints/cityscapes/${CHECKPOINTS_NAME}_latest.pth \
                       --checkpoints_name ${CHECKPOINTS_NAME} --pretrained ${PRETRAINED_MODEL} \
                       --base_lr 0.0001 \
                       2>&1 | tee -a ${LOG_FILE}


elif [ "$1"x == "val"x ]; then
  ${PYTHON} -u -m torch.distributed.launch main.py --configs ${CONFIGS} --drop_last y --train_batch_size ${BATCH_SIZE} --data_dir ${DATA_DIR} \
                       --backbone ${BACKBONE} --model_name ${MODEL_NAME} --checkpoints_name ${CHECKPOINTS_NAME} \
                       --phase test --gpu 2 --resume ${PRETRAINED_MODEL} \
                       --test_dir ${DATA_DIR}/test --log_to_file n --out_dir val 2>&1 | tee -a ${LOG_FILE}
  cd lib/metrics
  ${PYTHON} -u cityscapes_evaluator.py --pred_dir ../../results/cityscapes/test_dir/${CHECKPOINTS_NAME}/test/label \
                                       --gt_dir ${DATA_DIR}/test/label 2>&1 | tee -a ${LOG_FILE}

elif [ "$1"x == "test"x ]; then
  if [ "$3"x == "ss"x ]; then
    echo "[single scale] test"
    ${PYTHON} -u main.py --configs ${CONFIGS} --drop_last y \
                         --backbone ${BACKBONE} --model_name ${MODEL_NAME} --checkpoints_name ${CHECKPOINTS_NAME} \
                         --phase test --gpu 0 1 2 3 --resume ${PRETRAINED_MODEL} \
                         --test_dir ${DATA_DIR}test/image --log_to_file n \
                         --out_dir ${SAVE_DIR}${CHECKPOINTS_NAME}_test_ss
  else
    echo "[multiple scale + flip] test"
    ${PYTHON} -u main.py --configs ${CONFIGS} --drop_last y \
                         --backbone ${BACKBONE} --model_name ${MODEL_NAME} --checkpoints_name ${CHECKPOINTS_NAME} \
                         --phase test --gpu 0 1 2 3 --resume ./checkpoints/rs19/${CHECKPOINTS_NAME}_latest.pth \
                         --test_dir ${DATA_DIR}test --log_to_file n \
                         --out_dir ${SAVE_DIR}${CHECKPOINTS_NAME}_test_ms_6x_depth
  fi

else
  echo "$1"x" is invalid..."
fi