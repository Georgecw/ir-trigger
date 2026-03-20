#!/bin/bash

# ================= 配置区 =================
# 1. 这里一定要改成你的用户名！
TARGET_USER="george"

# 2. 你的摄像头路径
DEVICE="/dev/video0"

# 3. 命令的绝对路径 (使用 which 确认)
CMD_FUSER="/usr/bin/fuser"
CMD_SLEEP="/usr/bin/sleep"
CMD_DATE="/usr/bin/date"
CMD_SU="/usr/bin/su"
CMD_IR="/usr/local/bin/linux-enable-ir-emitter"

# 日志文件
LOG_FILE="/tmp/pam_ir_debug.log"

# linux-enable-ir-emitter 配置文件路径
CONFIG_FILE="/home/george/.config/linux-enable-ir-emitter.toml"

# 红外补光灯路径
VIDEO_DEVICE="/dev/video2"

CMD_RUNUSER="/usr/sbin/runuser"
# =========================================

# 固定亮度序列与每档停留时间
BRIGHTNESS_LEVELS=(0 5 10 20 30 40)
SLEEP_TIME=0.7 # 每个亮度停留的秒数

# =========================================
try_light() {
  for val in "${BRIGHTNESS_LEVELS[@]}"; do
    # 使用 sed 匹配 control = [...] 并替换为新的数值
    # 这里的正则专门针对你提供的 toml 格式
    sudo sed -i "s/control = \[.*\]/control = [$val]/" "$CONFIG_FILE"
    # 应用配置
    $CMD_RUNUSER -u "$TARGET_USER" -- "$CMD_IR" run >>"$LOG_FILE" 2>&1
    $CMD_SLEEP "$SLEEP_TIME"
  done
}

CURRENT_USER=$(whoami)
echo "$($CMD_DATE): [TRIGGER] Started as $CURRENT_USER." >"$LOG_FILE"

# 检查文件是否存在
if [ ! -f "$CONFIG_FILE" ]; then
  echo "错误: 找不到配置文件 $CONFIG_FILE" >>"$LOG_FILE"
  exit 0
fi

# 后台运行监控逻辑
(
  # 增加一个简单的文件锁，防止两个脚本进程同时疯狂发指令
  exec 200>/var/lock/ir_trigger.lock
  if ! flock -n 200; then
    echo "Another instance is already running, exiting." >>"$LOG_FILE"
    exit 0
  fi
  for i in {1..50}; do
    # 现在有了 seteuid，root 身份一定能检测到 root 的 howdy 占用
    if $CMD_FUSER "$DEVICE" >/dev/null 2>&1; then

      echo "$($CMD_DATE): Camera BUSY! Waiting for stabilization..." >>"$LOG_FILE"

      # 延时确保 howdy 的红外摄像头先打开（须根据 howdy config 的 frame_wait 调整）
      $CMD_SLEEP 0.5

      if [ "$CURRENT_USER" = "root" ]; then
        echo "Root detected. Using runuser to target $TARGET_USER." >>"$LOG_FILE"
        try_light
      else
        echo "Direct run as $CURRENT_USER." >>"$LOG_FILE"
        try_light
      fi
      echo "$($CMD_DATE): Success. IR Fired." >>"$LOG_FILE"
      exit 0
    fi
    $CMD_SLEEP 0.05
  done

  echo "$($CMD_DATE): Timeout (No camera usage detected)." >>"$LOG_FILE"
) &
exit 0
