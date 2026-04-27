#!/bin/sh

# ==========================================================
# OpenClash 直连流量监控脚本 (交互面板版)
# ==========================================================

SCRIPT_PATH="/usr/bin/oc_direct_check.sh"
LOG_FILE="/tmp/clash_direct_alerted.log"
CRON_CONF="/etc/crontabs/root"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
NC='\033[0m'

# --- 卸载函数 ---
do_uninstall() {
    echo -e "\n${BLUE}>>> 正在卸载 <<<${NC}"
    echo -e "1. 正在停止并移除定时任务..."
    sed -i "/oc_direct_check.sh/d" "$CRON_CONF"
    /etc/init.d/cron restart
    
    echo -e "2. 正在删除脚本和日志文件..."
    rm -f "$SCRIPT_PATH"
    rm -f "$LOG_FILE"
    
    echo -e "${GREEN}[OK] 卸载完成！${NC}\n"
}

# --- 安装函数 ---
do_install() {
    echo -e "\n${BLUE}>>> 开始配置与安装 <<<${NC}"
    read -p "请输入 OpenClash API 密钥 (无密码请直接回车): " API_SECRET
    read -p "请输入 TG Bot Token (必填): " TG_TOKEN
    read -p "请输入 TG Chat ID (必填): " TG_CHAT_ID

    if [ -z "$TG_TOKEN" ] || [ -z "$TG_CHAT_ID" ]; then
        echo -e "${RED}❌ 错误: Token 和 Chat ID 不能为空！返回主菜单。${NC}"
        sleep 2
        return
    fi

    echo -e "\n${YELLOW}[1/4]${NC} 正在安装依赖 (curl, jq)..."
    opkg update >/dev/null 2>&1
    opkg install curl jq >/dev/null 2>&1

    echo -e "${YELLOW}[2/4]${NC} 正在生成监控核心脚本..."
    cat << 'EOF' > "$SCRIPT_PATH"
#!/bin/sh
API_URL="http://127.0.0.1:9090"
# --- CONFIG START ---
API_SECRET="REPLACE_API_SECRET"
TG_TOKEN="REPLACE_TG_TOKEN"
TG_CHAT_ID="REPLACE_TG_CHAT_ID"
# --- CONFIG END ---

THRESHOLD=10485760
RECORD_FILE="/tmp/clash_direct_alerted.log"
touch "$RECORD_FILE"

if [ -n "$API_SECRET" ]; then
    API_RES=$(curl -s -H "Authorization: Bearer $API_SECRET" "$API_URL/connections")
else
    API_RES=$(curl -s "$API_URL/connections")
fi
[ -z "$API_RES" ] && exit 0

DATA=$(echo "$API_RES" | jq -r --argjson limit "$THRESHOLD" \
       '.connections[]? | select(.chains[]? | contains("DIRECT")) | select((.upload + .download) > $limit) | "\(.id)|\(.metadata.sourceIP)|\(.metadata.host)|\(.metadata.destinationIP)|\(.download)|\(.upload)"')

[ -z "$DATA" ] && exit 0

echo "$DATA" | while IFS="|" read -r id src host dst dl up; do
    if ! grep -q "^$id$" "$RECORD_FILE"; then
        DL_MB=$(awk "BEGIN {printf \"%.2f\", $dl/1048576}")
        UP_MB=$(awk "BEGIN {printf \"%.2f\", $up/1048576}")
        [ -z "$host" ] && host="$dst"
        MSG="⚠️ *OpenClash 直连大流量警告* %0A%0A*来源:* \`${src}\` %0A*目标:* \`${host}\` %0A*下载:* \`${DL_MB}MB\` %0A*上传:* \`${UP_MB}MB\`"
        curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" -d chat_id="${TG_CHAT_ID}" -d text="${MSG}" -d parse_mode="Markdown" >/dev/null
        echo "$id" >> "$RECORD_FILE"
    fi
done

# 清理已断开的 ID
CURRENT_IDS=$(echo "$API_RES" | jq -r '.connections[]?.id')
if [ -s "$RECORD_FILE" ]; then
    TEMP_FILE=$(mktemp)
    while read -r rid; do
        echo "$CURRENT_IDS" | grep -q "^$rid$" && echo "$rid" >> "$TEMP_FILE"
    done < "$RECORD_FILE"
    mv "$TEMP_FILE" "$RECORD_FILE"
fi
EOF

    # 填充配置
    sed -i "s/REPLACE_API_SECRET/$API_SECRET/g" "$SCRIPT_PATH"
    sed -i "s/REPLACE_TG_TOKEN/$TG_TOKEN/g" "$SCRIPT_PATH"
    sed -i "s/REPLACE_TG_CHAT_ID/$TG_CHAT_ID/g" "$SCRIPT_PATH"
    chmod +x "$SCRIPT_PATH"

    echo -e "${YELLOW}[3/4]${NC} 正在配置定时任务 (每分钟检测)..."
    sed -i "/oc_direct_check.sh/d" "$CRON_CONF"
    echo "* * * * * $SCRIPT_PATH >/dev/null 2>&1" >> "$CRON_CONF"
    /etc/init.d/cron restart

    echo -e "${GREEN}[4/4] 安装配置成功！系统将每分钟自动检测流量。${NC}\n"
}

# --- 交互面板主循环 ---
while true; do
    clear
    echo -e "${BLUE}====================================================${NC}"
    echo -e "${GREEN}       OpenClash 直连流量监控 TG 告警管理面板       ${NC}"
    echo -e "${BLUE}====================================================${NC}"
    echo "  1. 安装 或 重新配置监控脚本"
    echo "  2. 卸载 监控脚本"
    echo "  0. 退出脚本"
    echo -e "${BLUE}====================================================${NC}"
    
    read -p "请输入数字选择操作 [0-2]: " choice
    
    case "$choice" in
        1)
            do_install
            read -p "按回车键继续..."
            ;;
        2)
            do_uninstall
            read -p "按回车键继续..."
            ;;
        0)
            echo -e "\n退出脚本。祝使用愉快！\n"
            exit 0
            ;;
        *)
            echo -e "${RED}输入无效，请重新输入！${NC}"
            sleep 1
            ;;
    esac
done
