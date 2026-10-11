#!/usr/bin/env bash
# 安装 AWS CLI v2，写入 /root/.aws/config 与 credentials，并输出 S3 存储类型说明和上传示例
# 用法：sudo ./install_awscli.sh
#      或通过环境变量覆盖：sudo AK=xxx SK=yyy BUCKET=my-bucket REGION=ap-southeast-1 ./install_awscli.sh
# curl -fsSl https://raw.githubusercontent.com/mudocli/shares/main/awscli.Install.sh | sudo AK=xxx SK=yyy BUCKET=my-bucket bash


set -euo pipefail

# ================== 变量 ==================
BUCKET="${BUCKET:-}"
AK="${AK:-}"
SK="${SK:-}"
REGION="${REGION:-}"
AWS_DIR="/root/.aws"
# ==========================================

[[ $EUID -eq 0 ]] || { echo "请用 root 执行"; exit 1; }

# ---------- 1. 安装 AWS CLI v2 ----------
if command -v aws >/dev/null 2>&1 && aws --version 2>&1 | grep -q 'aws-cli/2'; then
  echo "[1/3] 已安装：$(aws --version 2>&1)，跳过安装"
else
  echo "[1/3] 安装 AWS CLI v2 ..."
  case "$(uname -m)" in
    x86_64)  ARCH=x86_64 ;;
    aarch64) ARCH=aarch64 ;;
    *) echo "不支持的架构：$(uname -m)"; exit 1 ;;
  esac

  for pkg in curl unzip; do
    if ! command -v "$pkg" >/dev/null 2>&1; then
      if command -v yum >/dev/null 2>&1; then yum install -y "$pkg"
      elif command -v dnf >/dev/null 2>&1; then dnf install -y "$pkg"
      elif command -v apt-get >/dev/null 2>&1; then apt-get update && apt-get install -y "$pkg"
      else echo "请先手动安装 $pkg"; exit 1; fi
    fi
  done

  TMP=$(mktemp -d)
  trap 'rm -rf "$TMP"' EXIT
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${ARCH}.zip" -o "$TMP/awscliv2.zip"
  unzip -q "$TMP/awscliv2.zip" -d "$TMP"
  # 已存在 v1（如系统自带 /usr/bin/aws）时用 --update 覆盖
  "$TMP/aws/install" --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli --update
  hash -r
  echo "安装完成：$(/usr/local/bin/aws --version 2>&1)"
fi

AWS=$(command -v aws || echo /usr/local/bin/aws)

# ---------- 2. 写入配置文件 ----------
echo "[2/3] 写入 $AWS_DIR ..."
mkdir -p "$AWS_DIR"
chmod 700 "$AWS_DIR"

cat > "$AWS_DIR/config" <<EOF
[default]
region = ${REGION}
EOF

cat > "$AWS_DIR/credentials" <<EOF
[default]
aws_access_key_id = ${AK}
aws_secret_access_key = ${SK}
EOF
chmod 600 "$AWS_DIR/config" "$AWS_DIR/credentials"

echo "---- $AWS_DIR/config"
cat "$AWS_DIR/config"
echo "---- $AWS_DIR/credentials（已脱敏）"
sed -E 's/(= ?).{4}(.*)(.{4})$/\1****…\3/' "$AWS_DIR/credentials"

# ---------- 3. 验证 ----------
echo "[3/3] 验证 ..."
if [[ -z "$AK" || -z "$SK" ]]; then
  echo "AK/SK 为空，跳过验证。填好变量后重新执行，或手动编辑 $AWS_DIR/credentials"
else
  if "$AWS" sts get-caller-identity --output text; then
    "$AWS" s3 ls "s3://${BUCKET}" >/dev/null 2>&1 \
      && echo "Bucket s3://${BUCKET} 可访问" \
      || echo "警告：无法访问 s3://${BUCKET}，检查桶名、区域或 IAM 权限"
  else
    echo "警告：凭证验证失败，检查 AK/SK"
  fi
fi

# ---------- 存储类型说明与上传示例 ----------
cat <<EOF

======================== S3 存储类型说明 ========================

[GLACIER_IR] Glacier Instant Retrieval（即时检索归档）
  - 适合：很少访问（约每季度一次），但需要随时毫秒级取回的数据
          如历史日志、合规归档、旧备份
  - 读取：毫秒级，和 STANDARD 一样直接下载，无需先 restore
  - 存储费比 ONEZONE_IA 更低，但读取（检索）费更高
  - 最短计费 90 天：90 天内删除或覆盖，仍按 90 天收费
  - 最小计费对象 128KB：小文件按 128KB 计
  - 多可用区冗余存储

[ONEZONE_IA] One Zone-Infrequent Access（单可用区低频访问）
  - 适合：不常访问、丢了可以重新生成的数据
          如二级备份副本、可重算的中间数据
  - 读取：毫秒级，有按 GB 计的检索费
  - 存储费比 STANDARD_IA 低，读取费比 GLACIER_IR 低
  - 最短计费 30 天，最小计费对象 128KB
  - 只存在一个可用区：该可用区故障或损毁时数据可能丢失
    不要用来存唯一的一份重要数据

选择建议：
  - 一个月内可能要读，或 30~90 天后就删除 → ONEZONE_IA
  - 长期保存、极少读取、要求多可用区可靠性 → GLACIER_IR

========================== 上传示例 ============================

BUCKET=${BUCKET}
HOST=\$(hostname)

# 单个文件
aws s3 cp app.log.gz s3://\$BUCKET/\$HOST/app.log.gz --storage-class ONEZONE_IA

# 批量上传当前目录的 *.gz（ONEZONE_IA）
for i in *.gz; do
  aws s3 cp "\$i" "s3://\$BUCKET/\$HOST/\$i" --storage-class ONEZONE_IA
done

# 批量上传（GLACIER_IR）
for i in *.gz; do
  aws s3 cp "\$i" "s3://\$BUCKET/\$HOST/\$i" --storage-class GLACIER_IR
done

# 整个目录增量同步（只传新增或变化的文件）
aws s3 sync /data/backup s3://\$BUCKET/\$HOST/ --storage-class GLACIER_IR

# 查看上传后的存储类型
aws s3api head-object --bucket \$BUCKET --key \$HOST/app.log.gz --query StorageClass
================================================================
EOF
