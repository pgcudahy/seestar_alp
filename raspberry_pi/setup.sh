#!/bin/bash -e

#
# common functions
#
function validate_access {
  if [ "$(whoami)" = "root" ]; then
    echo "ERROR: You should not run this script as root"
    exit 255
  fi

  sudo -n id 2>&1 > /dev/null && sudo="true" || sudo="false"
  if [ "$sudo" = "false" ]; then
    echo "ERROR: User does not have sudo access required for setup"
    exit 255
  fi

  if [ "$(arch)" != "aarch64" ]; then
    echo "ERROR: Unsupported architecture. Please ensure you are running the 64bit raspberry pi OS"
    exit 255
  fi

  if [ "$(uname)" != "Linux" ]; then
    echo "ERROR: You should only run this script on a Linux machine"
  fi
}

function install_apt_packages {
  sudo apt-get update --yes
  sudo apt-get install --yes software-properties-common \
    git libssl-dev zlib1g-dev libbz2-dev libreadline-dev \
    libsqlite3-dev llvm libncurses5-dev libncursesw5-dev \
    xz-utils tk-dev libgdbm-dev lzma lzma-dev tcl-dev \
    libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev \
    wget curl make build-essential openssl libgl1 indi-bin
}

function config_toml_setup {
  if [ ! -e device/config.toml ]; then
    cp device/config.toml.example device/config.toml
    sed -i -e 's/127.0.0.1/0.0.0.0/g' device/config.toml
    sed -i -e 's|log_prefix =.*|log_prefix = "logs/"|g' device/config.toml
  else
    cp device/config.toml device/config.toml.bak
  fi
}

function python_virtualenv_setup {
  if [ ! -e ~/.pyenv ]; then
    curl https://pyenv.run | bash
    cat <<_EOF >> ~/.bashrc
# start seestar_alp
export PYENV_ROOT="\$HOME/.pyenv"
[[ -d \$PYENV_ROOT/bin ]] && export PATH="\$PYENV_ROOT/bin:\$PATH"
eval "\$(pyenv init -)"
eval "\$(pyenv virtualenv-init -)"
# end seestar_alp
_EOF

    export PYENV_ROOT="$HOME/.pyenv"
    [[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
    eval "$(pyenv init -)"
    eval "$(pyenv virtualenv-init -)"

    pyenv install 3.12.5
    pyenv virtualenv 3.12.5 ssc-3.12.5

    pyenv global ssc-3.12.5

  else
    export PYENV_ROOT="$HOME/.pyenv"
    [[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
    eval "$(pyenv init -)"
    eval "$(pyenv virtualenv-init -)"
  fi

  pip install -r requirements.txt
}

function systemd_service_setup {
  cd raspberry_pi

  cat systemd/seestar.env |sed -e "s/<username>/$USER/g" > /tmp/seestar.env

  cat systemd/seestar.service | sed \
  -e "s|/home/.*/seestar_alp|$src_home|g" \
  -e "s|^User=.*|User=${user}|g" \
  -e "s|^ExecStart=.*|ExecStart=$HOME/.pyenv/versions/ssc-3.12.5/bin/python3 $src_home/root_app.py|" > /tmp/seestar.service

  cat systemd/INDI.service | sed \
  -e "s|/home/.*/seestar_alp|$src_home|g" \
  -e "s|^User=.*|User=${user}|g" > /tmp/INDI.service

  sudo chown root:root /tmp/seestar.service /tmp/INDI.service /tmp/seestar.env
  sudo mv /tmp/seestar.service /etc/systemd/system
  sudo mv /tmp/INDI.service /etc/systemd/system
  sudo mv /tmp/seestar.env /etc

  sudo systemctl daemon-reload

  sudo systemctl enable seestar
  sudo systemctl start seestar

  sudo systemctl enable INDI
  sudo systemctl start INDI

  # INDI service left disabled

  if ! $(systemctl is-active --quiet seestar); then
    echo "ERROR: seestar service is not running"
    systemctl status seestar
    exit 255
  fi
}

function network_config {
  sudo bash -c 'echo "net.ipv6.conf.all.disable_ipv6 = 1" > /etc/sysctl.d/98-ssc.conf'
  sudo sysctl -p
}

function print_banner {
  local operation="$1"
  local host=$(hostname)
  cat <<_EOF
|-------------------------------------|
$(printf "| %-36s|" "Seestar_alp ${operation} complete")
|                                     |
| You can access SSC via:             |
$(printf "| %-36s|" "http://${host}.local:5432")
|                                     |
| Device logs can be found in         |
|  ./seestar_alp/logs                 |
|                                     |
| Systemd logs can be viewed via      |
| journalctl -u seestar               |
| journalctl -u INDI                  |
|                                     |
| Current status can be viewed via    |
| systemctl status seestar            |
| systemctl status INDI               |
|-------------------------------------|
_EOF
}

#
# main setup script
#
function setup() {
  validate_access

  if [ -e seestar_alp ] || [ -e ~/seestar_alp ]; then
    echo "ERROR: Existing seestar_alp directory detected."
    echo "       You should run the raspberry_pi/update.sh script instead."
    exit 255
  fi

  install_apt_packages
  git clone -b release_2.5.x https://github.com/smart-underworld/seestar_alp.git
  cd  seestar_alp

  user=$(whoami)
  group=$(id -gn)
  src_home=$(pwd)
  mkdir -p logs

  config_toml_setup
  python_virtualenv_setup
  network_config
  systemd_service_setup
  print_banner "setup"
}

#
# run setup if not sourced from another file
#
(return 0 2>/dev/null) && sourced=1 || sourced=0
if [ ${sourced} = 0 ]; then
  setup
fi
