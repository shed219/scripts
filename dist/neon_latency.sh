#!/bin/bash
# ============================================
# Neon AWS 区域延迟测试 - 专业版
# 支持: TCP Ping、结果排序、颜色输出
# 无需 bc，纯 bash 整数运算
# ============================================

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

declare -A REGIONS=(
  ["US East 1 (N. Virginia)"]="ec2.us-east-1.amazonaws.com"
  ["US East 2 (Ohio)"]="ec2.us-east-2.amazonaws.com"
  ["US West 2 (Oregon)"]="ec2.us-west-2.amazonaws.com"
  ["Asia Pacific 1 (Singapore)"]="ec2.ap-southeast-1.amazonaws.com"
  ["Asia Pacific 2 (Sydney)"]="ec2.ap-southeast-2.amazonaws.com"
  ["Europe Central 1 (Frankfurt)"]="ec2.eu-central-1.amazonaws.com"
  ["Europe West 2 (London)"]="ec2.eu-west-2.amazonaws.com"
  ["South America East 1 (Sao Paulo)"]="ec2.sa-east-1.amazonaws.com"
)

PING_COUNT=5
PORT=443
TIMEOUT=5
RESULTS=()

get_color() {
  local ms=$1
  if [[ "$ms" =~ ^[0-9]+$ ]] && (( ms < 100 )); then
    echo -e "${GREEN}"
  elif [[ "$ms" =~ ^[0-9]+$ ]] && (( ms < 200 )); then
    echo -e "${YELLOW}"
  else
    echo -e "${RED}"
  fi
}

tcp_ping() {
  local host=$1
  local latencies=()

  for i in $(seq 1 $PING_COUNT); do
    local start end diff
    start=$(date +%s%N)
    if timeout $TIMEOUT bash -c "exec 3<>/dev/tcp/${host}/${PORT}" 2>/dev/null; then
      end=$(date +%s%N)
      diff=$(( (end - start) / 1000000 ))
      latencies+=($diff)
      exec 3>&- 2>/dev/null
    fi
    sleep 0.2
  done

  if [ ${#latencies[@]} -eq 0 ]; then
    echo "timeout"
    return
  fi

  local sum=0 min=${latencies[0]} max=${latencies[0]}
  for v in "${latencies[@]}"; do
    sum=$((sum + v))
    (( v < min )) && min=$v
    (( v > max )) && max=$v
  done
  local avg=$((sum / ${#latencies[@]}))

  echo "${min}|${avg}|${max}|${#latencies[@]}"
}

echo ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${CYAN}║          Neon Database 区域延迟测试 (TCP Port 443)              ║${NC}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════════╝${NC}"
echo -e "${BOLD}$(printf '%-38s %-10s %-10s %-10s %-8s\n' '区域' '最低(ms)' '平均(ms)' '最高(ms)' '成功/总数')${NC}"
echo -e "─────────────────────────────────────────────────────────────────"

for region in "${!REGIONS[@]}"; do
  host="${REGIONS[$region]}"
  echo -ne "  测试中: ${region}...   \r"

  result=$(tcp_ping "$host")

  if [ "$result" == "timeout" ]; then
    printf "%-38s ${RED}%-10s %-10s %-10s %-8s${NC}\n" \
      "$region" "超时" "-" "-" "0/${PING_COUNT}"
    RESULTS+=("9999|9999|9999|$region|0")
  else
    IFS='|' read -r mn avg mx cnt <<< "$result"
    color=$(get_color "$avg")
    printf "%-38s ${color}%-10s %-10s %-10s${NC} %-8s\n" \
      "$region" "${mn}ms" "${avg}ms" "${mx}ms" "${cnt}/${PING_COUNT}"
    RESULTS+=("${avg}|${mn}|${mx}|${region}|${cnt}")
  fi
done

echo -e "─────────────────────────────────────────────────────────────────"

SORTED=$(printf '%s\n' "${RESULTS[@]}" | sort -t'|' -k1 -n)
BEST=$(echo "$SORTED" | head -1)
IFS='|' read -r avg mn mx best_region cnt <<< "$BEST"

echo ""
if [ "$avg" != "9999" ]; then
  echo -e "${GREEN}${BOLD}🏆 最优区域: ${best_region}${NC}"
  echo -e "${GREEN}   平均延迟: ${avg}ms | 最低: ${mn}ms${NC}"
else
  echo -e "${RED}所有区域均超时，请检查网络连接。${NC}"
fi

OUTPUT_FILE="neon_latency_$(date +%Y%m%d_%H%M%S).txt"
{
  echo "Neon 区域延迟测试结果 - $(date)"
  echo "================================================"
  printf '%-38s %-10s %-10s %-10s\n' '区域' '最低(ms)' '平均(ms)' '最高(ms)'
  echo "------------------------------------------------"
  while IFS= read -r r; do
    IFS='|' read -r avg mn mx region cnt <<< "$r"
    printf '%-38s %-10s %-10s %-10s\n' "$region" "${mn}ms" "${avg}ms" "${mx}ms"
  done <<< "$SORTED"
} > "$OUTPUT_FILE"

echo ""
echo -e "${CYAN}📄 结果已保存到: ${OUTPUT_FILE}${NC}"
echo ""
