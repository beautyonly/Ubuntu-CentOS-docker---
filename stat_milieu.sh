#!/bin/bash

# set -xe

# 系统添加用户
function system_add_user() {
  if [ -z "$1" ]; then
    echo "Usage: system_add_user <username>"
    return 1
  fi

  local user=$1
  sudo adduser $user
  # 允许用户 sudo
  case "$LSB_DIST" in
    Ubuntu) sudo usermod -aG sudo $user   ;;
    CentOS) sudo usermod -aG wheel $user  ;;
    *)      echo "Not Supported System."  ;;
  esac

  # 允许用户使用 docker
  sudo groupadd -f docker
  sudo usermod -aG docker $user
  # 允许用户管理 目录 xx7服务
  sudo groupadd -f xx7
  sudo usermod -aG xx7 $user
}

# 系统常用设置
function system_common_setup() {
  local server_name=$HOSTNAME
  # Timezone 时区
  sudo timedatectl set-timezone Asia/Shanghai
  # Locale 区域设置
  sudo localectl set-locale LANG=en_US.utf8
  # Hostname 主机名
  local old_hostname=$(hostname)
  sudo sed -i "s/$old_hostname/$server_name/g" /etc/hosts
  sleep 1id
  sudo hostnamectl set-hostname $server_name

  # Elastic Search 需要 vm.max_map_count 至少为 262144
  echo "vm.max_map_count=262144" | sudo tee /etc/sysctl.d/50-elasticsearch.conf

  # Redis 备份需要 fork 内存，因此为了避免 double 内存，可以设置 overcommit_memory=1
  echo "vm.overcommit_memory=1" | sudo tee /etc/sysctl.d/50-redis.conf
}

# [CentOS] 安装常用工具
function system_install_centos() {
  # sudo yum install epel-release
  sudo yum install -y \
    git \
    tree \
    etckeeper \
    pv \
    jq
}

# [Ubuntu] 安装常用工具
function system_install_ubuntu() {
  cat <<EOF | sudo tee /etc/apt/apt.conf.d/50no-recommends
APT::Get::Install-Recommends "false";
APT::Get::Install-Suggests "false";
EOF

  sudo apt-get update
  sudo apt-get dist-upgrade -y
  sudo apt-get install -y \
    apt-transport-https \
    curl \
    gnupg-curl \
    git \
    htop \
    lsof \
    tree \
    etckeeper \
    pv \
    jq \
    tzdata \
    strace \
    lsb-release \
    zsh \
    zsh-antigen \
    rsync \
    zsh-syntax-highlighting
}

# 安装 Docker
function system_install_docker() {
  echo "安装 Docker..."

  # Docker
  export CHANNEL=stable
  curl -fsSL https://get.docker.com/ | sh
  ## Add Docker daemon configuration
  cat <<EOF | sudo tee /etc/docker/daemon.json
{
  "icc": false,
  "disable-legacy-registry": true,
  "userland-proxy": false,
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "5"
  },
  "live-restore": true
}
EOF

#   ## 为 Docker 添加审计
#   cat <<EOF | sudo tee /etc/audit/rules.d/audit.rules
# -w /etc/docker -k docker
# -w /etc/docker/daemon.json -k docker
# -w /etc/default/docker -k docker
# -w /usr/lib/systemd/system/docker.service -k docker
# EOF
  ### https://bugzilla.redhat.com/show_bug.cgi?id=1026648
  #sudo service auditd restart

  ## 启动 Docker 服务
  sudo systemctl enable docker
  sudo systemctl start docker
  ## 添加当前用户至 docker 组
  sudo usermod -aG docker $USER

  case "$LSB_DIST" in
    CentOS)
      ## enable 'net.bridge.bridge-nf-call-iptables'
      cat <<EOF | sudo tee /etc/sysctl.d/50-docker.conf
# For Docker
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF
      sudo sysctl --system
      ;;
    Ubuntu)
      sudo sed -i 's/GRUB_CMDLINE_LINUX=""/GRUB_CMDLINE_LINUX="cgroup_enable=memory swapaccount=1"/' /etc/default/grub
      sudo update-grub
      ;;
  esac

  ## show information
  docker version
  docker info

  # Docker Compose
  sudo curl -L https://github.com/docker/compose/releases/download/1.16.1/docker-compose-`uname -s`-`uname -m` -o /usr/local/bin/docker-compose
  sudo chmod +x /usr/local/bin/docker-compose
  ## show docker-compose version
  docker-compose version
}

# 检查 Docker 系统安全性
function docker_bench_security() {
  docker run -it --net host --pid host --cap-add audit_control \
    -e DOCKER_CONTENT_TRUST=$DOCKER_CONTENT_TRUST \
    -v /var/lib:/var/lib \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v /usr/lib/systemd:/usr/lib/systemd \
    -v /etc:/etc --label docker_bench_security \
    docker/docker-bench-security
}

# 进一步的封装

# 宿主系统初始化
function system_provision() {
  case "$LSB_DIST" in
    Ubuntu) system_install_ubuntu   ;;
    CentOS) system_install_centos  ;;
    *)      echo "Not Supported System."  ;;
  esac

  system_common_setup
  system_install_docker
}

# 对备份目录进行列表
function backup_list() {
  tree -th -L 2 ./backup
}

# 程序入口
command=$1
shift
$command "$@"
