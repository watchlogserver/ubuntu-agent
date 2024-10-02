#!/bin/bash
# Define the log file path
LOG_FILE="watchlog_install.log"

# Function to log error messages
log_error() {
    echo "[ERROR] $(date): $1" >> "$LOG_FILE"
    echo "[ERROR] $1" >&2
}

# Create the log file
touch "$LOG_FILE"

# Step 1: Check for required environment variables
if [ -z "$apiKey" ] || [ -z "$server" ]; then
    log_error "Required environment variables (apiKey and server) are not set."
    exit 1
fi

# Step 2: Check if Node.js is installed
if ! command -v node &> /dev/null
then
    echo "Node.js is not installed. Do you want to install it? (Y/N)"
    read install_node
    if [[ "$install_node" == "Y" || "$install_node" == "y" ]]; then
        # Install Node.js
        curl -fsSL https://deb.nodesource.com/setup_16.x | sudo -E bash - >> $LOG_FILE 2>&1
        sudo apt-get install -y nodejs >> $LOG_FILE 2>&1
        if [ $? -ne 0 ]; then
            log_error "Failed to install Node.js."
            exit 1
        fi
        echo "Node.js installed successfully."
    else
        echo "Node.js is required to install the agent. Exiting."
        exit 1
    fi
fi

# Step 3: Download the .deb package
wget -O watchlog-agent.deb https://watchlog.io/watchlog-agent.deb >> $LOG_FILE 2>&1
if [ $? -ne 0 ]; then
    log_error "Failed to download the watchlog-agent package."
    exit 1
fi

# Step 4: Install the package
dpkg-deb -R ./watchlog-agent.deb watchlog-agent
echo "WATCHLOG_APIKEY=$apiKey" | tee ./watchlog-agent/src/.env >/dev/null
echo "WATCHLOG_SERVER=$server" | tee -a ./watchlog-agent/src/.env >/dev/null
cp -R ./watchlog-agent /opt/watchlog-agent
cp ./watchlog-agent/DEBIAN/watchlog-agent.service /etc/systemd/system/watchlog-agent.service

# Step 5: Start the agent
systemctl start watchlog-agent >> $LOG_FILE 2>&1
if [ $? -ne 0 ]; then
    log_error "Failed to start the watchlog-agent service."
    exit 1
fi

echo "Watchlog agent installed and started successfully."
sudo rm watchlog_install.log
sudo rm -R ./watchlog-agent
sudo rm -R ./watchlog-agent.deb
