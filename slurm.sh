#!/bin/bash


set -e

print_msg() {
    echo "========================================"
    echo "$1"
    echo "========================================"
}

prompt_with_default() {
    local prompt_message=$1
    local default_value=$2
    read -p "$prompt_message [$default_value]: " user_input
    if [ -z "$user_input" ]; then
        echo "$default_value"
    else
        echo "$user_input"
    fi
}

check_slurm_version() {
    local version=$1
    local url="https://download.schedmd.com/slurm/slurm-${version}.tar.bz2"
    if wget --spider -q "$url"; then
        echo "$url"
    else
        echo ""
    fi
}

DEFAULT_SLURM_VERSION="24.05.5"
echo "Enter the Slurm version you want to install (e.g., 24.05.5):"
read -p "Version [${DEFAULT_SLURM_VERSION}]: " SLURM_VERSION_INPUT

SLURM_VERSION=${SLURM_VERSION_INPUT:-$DEFAULT_SLURM_VERSION}

SLURM_DOWNLOAD_URL=$(check_slurm_version "$SLURM_VERSION")
if [ -z "$SLURM_DOWNLOAD_URL" ]; then
    echo "Version ${SLURM_VERSION} does not exist. Falling back to default version ${DEFAULT_SLURM_VERSION}."
    SLURM_VERSION=$DEFAULT_SLURM_VERSION
    SLURM_DOWNLOAD_URL=$(check_slurm_version "$SLURM_VERSION")
    if [ -z "$SLURM_DOWNLOAD_URL" ]; then
        echo "Default Slurm version ${DEFAULT_SLURM_VERSION} is also unavailable. Exiting."
        exit 1
    fi
else
    echo "Slurm version ${SLURM_VERSION} is available."
fi

SLURM_TARBALL="slurm-${SLURM_VERSION}.tar.bz2"
SLURM_URL="$SLURM_DOWNLOAD_URL"


DEFAULT_INSTALL_PREFIX="/opt/slurm"
INSTALL_PREFIX=$(prompt_with_default "Enter installation prefix" "$DEFAULT_INSTALL_PREFIX")


DEFAULT_SLURM_USER="ubuntu"
SLURM_USER=$(prompt_with_default "Enter Slurm user" "$DEFAULT_SLURM_USER")


DEFAULT_SLURM_GROUP="ubuntu"
SLURM_GROUP=$(prompt_with_default "Enter Slurm group" "$DEFAULT_SLURM_GROUP")


SLURM_CONF_DIR="/etc/slurm"
SLURM_CONF="${SLURM_CONF_DIR}/slurm.conf"
NUM_CPUS=$(nproc)
BASHRC="$HOME/.bashrc"


print_msg "Installing build dependencies and additional packages..."
sudo apt-get update
sudo apt-get install -y build-essential libpam0g-dev libmunge-dev munge libssl-dev \
    libreadline-dev libncurses5-dev libhwloc-dev hwloc libmunge2 wget curl


print_msg "Setting up Munge..."
sudo mkdir -p /etc/munge

if [ ! -f /etc/munge/munge.key ]; then
    if sudo /usr/sbin/create-munge-key; then
        echo "Munge key created successfully."
    else
        echo "Failed to create Munge key using create-munge-key. Attempting alternative method."
        sudo dd if=/dev/urandom bs=1 count=1024 > /etc/munge/munge.key
    fi
    sudo chown munge:munge /etc/munge/munge.key
    sudo chmod 400 /etc/munge/munge.key
fi

sudo mkdir -p /var/lib/munge /var/log/munge
sudo chown -R munge:munge /var/lib/munge /var/log/munge
sudo chmod 755 /var/lib/munge /var/log/munge
sudo systemctl enable munge
sudo systemctl start munge


print_msg "Creating Slurm user and group..."
if ! getent group "${SLURM_GROUP}" > /dev/null 2>&1; then
    sudo groupadd --system "${SLURM_GROUP}"
    echo "Group ${SLURM_GROUP} created."
else
    echo "Group ${SLURM_GROUP} already exists."
fi

if ! id -u "${SLURM_USER}" > /dev/null 2>&1; then
    sudo useradd --system --gid "${SLURM_GROUP}" --shell /bin/false --comment "Slurm Workload Manager" "${SLURM_USER}"
    echo "User ${SLURM_USER} created."
else
    echo "User ${SLURM_USER} already exists."
fi


TEMP_DIR=$(mktemp -d)
print_msg "Created temporary directory at ${TEMP_DIR}"
cd "${TEMP_DIR}"


print_msg "Downloading Slurm ${SLURM_VERSION}..."
wget -q "${SLURM_URL}" || { echo "Failed to download Slurm tarball from ${SLURM_URL}. Exiting."; exit 1; }


print_msg "Extracting ${SLURM_TARBALL}..."
tar -xjf "${SLURM_TARBALL}"


cd "slurm-${SLURM_VERSION}"


print_msg "Configuring the Slurm build..."
./configure --prefix="${INSTALL_PREFIX}" --with-pam --with-slurmctld-user="${SLURM_USER}"


print_msg "Compiling Slurm using ${NUM_CPUS} cores..."
make -j "${NUM_CPUS}"


print_msg "Installing Slurm..."
sudo make install

print_msg "Creating necessary directories..."
sudo mkdir -p /var/spool/slurm/slurmd
sudo mkdir -p /var/spool/slurm/slurmctld
sudo mkdir -p /var/log/slurm

print_msg "Setting ownership to ${SLURM_USER}:${SLURM_GROUP}..."
sudo chown -R "${SLURM_USER}:${SLURM_GROUP}" /var/spool/slurm
sudo chown -R "${SLURM_USER}:${SLURM_GROUP}" /var/log/slurm

print_msg "Gathering system information for slurm.conf..."
TOTAL_CPUS=$(nproc)
TOTAL_MEMORY=$(free -m | awk '/^Mem:/{print $2}')

print_msg "Creating slurm.conf at ${SLURM_CONF}..."
sudo mkdir -p "${SLURM_CONF_DIR}"
sudo tee "${SLURM_CONF}" > /dev/null <<EOL
# BASIC SETTINGS
ClusterName=single_machine_cluster
SlurmctldHost=localhost               # Slurm controller is the same machine
ProctrackType=proctrack/pgid
ReturnToService=1
SlurmctldPort=6817
SlurmdPort=6818
SlurmdSpoolDir=/var/spool/slurm/slurmd
SlurmUser=${SLURM_USER}                      # Use the slurm user
StateSaveLocation=/var/spool/slurm/slurmctld
TaskPlugin=task/affinity

# SCHEDULING
SchedulerType=sched/backfill
SelectType=select/cons_res
SelectTypeParameters=CR_CPU_Memory

# LOGGING
SlurmctldDebug=info
SlurmctldLogFile=/var/log/slurmctld.log
SlurmdDebug=info
SlurmdLogFile=/var/log/slurmd.log

# COMPUTE NODE
NodeName=localhost NodeAddr=127.0.0.1 CPUs=${TOTAL_CPUS} RealMemory=${TOTAL_MEMORY} State=UNKNOWN

# PARTITION
PartitionName=single_partition Nodes=localhost Default=YES MaxTime=INFINITE State=UP
EOL

sudo chown "${SLURM_USER}:${SLURM_GROUP}" "${SLURM_CONF}"
sudo chmod 644 "${SLURM_CONF}"

print_msg "Updating ${BASHRC} to include Slurm binaries..."
if ! grep -q "${INSTALL_PREFIX}/bin" "${BASHRC}"; then
    echo "" >> "${BASHRC}"
    echo "# Slurm binaries" >> "${BASHRC}"
    echo "export PATH=${INSTALL_PREFIX}/bin:${INSTALL_PREFIX}/sbin:\$PATH" >> "${BASHRC}"
    echo "Slurm binaries added to PATH."
else
    echo "Slurm binaries already in PATH."
fi

print_msg "Sourcing ${BASHRC}..."
if [ "$SUDO_USER" ]; then
    sudo -u "${SUDO_USER}" bash -c "source ${BASHRC}"
else
    source "${BASHRC}"
fi

print_msg "Creating systemd service for slurmctld..."
sudo tee /etc/systemd/system/slurmctld.service > /dev/null <<EOL
[Unit]
Description=Slurm Controller Daemon
After=network.target munge.service

[Service]
Type=simple
ExecStart=${INSTALL_PREFIX}/sbin/slurmctld
User=${SLURM_USER}
Group=${SLURM_GROUP}
PIDFile=/var/run/slurmctld.pid
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOL


print_msg "Creating systemd service for slurmd..."
sudo tee /etc/systemd/system/slurmd.service > /dev/null <<EOL
[Unit]
Description=Slurm Node Daemon
After=network.target munge.service

[Service]
Type=simple
ExecStart=${INSTALL_PREFIX}/sbin/slurmd
User=${SLURM_USER}
Group=${SLURM_GROUP}
PIDFile=/var/run/slurmd.pid
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOL


print_msg "Reloading systemd daemon..."
sudo systemctl daemon-reload


print_msg "Enabling and starting slurmctld and slurmd services..."
sudo systemctl enable slurmctld
sudo systemctl enable slurmd
sudo systemctl start slurmctld
sudo systemctl start slurmd


print_msg "Cleaning up temporary files..."
cd ~
rm -rf "${TEMP_DIR}"

print_msg "Slurm installation and configuration completed successfully!"

echo ""
print_msg "Service Status:"
sudo systemctl status slurmctld --no-pager
sudo systemctl status slurmd --no-pager
