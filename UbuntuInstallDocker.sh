#!/usr/bin/env bash
# Ubuntu 安装 Docker CE（官方源）
# 用法：sudo ./install_docker_ubuntu.sh
# 或：curl -fsSL https://raw.githubusercontent.com/mudocli/shares/main/UbuntuInstallDocker.sh | sudo bash

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

[[ $EUID -eq 0 ]] || { echo "请用 root 或 sudo 执行"; exit 1; }

. /etc/os-release
[[ "${ID:-}" == "ubuntu" ]] || { echo "仅支持 Ubuntu，当前系统：${PRETTY_NAME:-未知}"; exit 1; }
CODENAME="${UBUNTU_CODENAME:-$VERSION_CODENAME}"
echo ">>> 系统：$PRETTY_NAME（$CODENAME），架构：$(dpkg --print-architecture)"

# ---------- 1. 卸载冲突的旧包 ----------
echo ">>> [1/5] 卸载冲突的旧包"
OLD_PKGS=$(dpkg --get-selections docker.io docker-compose docker-compose-v2 docker-doc \
             docker-buildx podman-docker containerd runc 2>/dev/null \
           | awk '$2=="install"{print $1}' || true)
if [[ -n "$OLD_PKGS" ]]; then
  echo "    将卸载：$(echo $OLD_PKGS)"
  apt-get remove -y $OLD_PKGS
else
  echo "    没有需要卸载的旧包"
fi

# ---------- 2. 添加 Docker 官方 GPG key ----------
echo ">>> [2/5] 添加 Docker 官方 GPG key"
apt-get update
apt-get install -y ca-certificates curl
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

# ---------- 3. 添加 Docker 源 ----------
echo ">>> [3/5] 添加 Docker apt 源"
tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${CODENAME}
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF
cat /etc/apt/sources.list.d/docker.sources

# ---------- 4. 安装 Docker ----------
echo ">>> [4/5] 安装 Docker"
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# ---------- 5. 启动并设置开机自启 ----------
echo ">>> [5/5] 启动并设置开机自启"
systemctl enable --now docker
systemctl status docker --no-pager --lines=5 || true

# 如果是普通用户通过 sudo 执行，把该用户加入 docker 组（重新登录后免 sudo 使用 docker）
if [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != "root" ]]; then
  usermod -aG docker "$SUDO_USER"
  echo "    已将 $SUDO_USER 加入 docker 组，重新登录后生效"
fi

echo
echo "================ 安装完成 ================"
docker --version
docker compose version
echo "开机自启：$(systemctl is-enabled docker)，运行状态：$(systemctl is-active docker)"
echo "验证可执行：docker run --rm hello-world"
