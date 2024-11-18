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

# Check if the Watchlog agent is already installed
if systemctl list-unit-files | grep -q "watchlog-agent.service"; then
    # Check if the Watchlog agent is running
    if systemctl is-active --quiet watchlog-agent; then
        echo "The Watchlog agent is already installed and running on this server."
        echo "If you want to update or remove the agent, please refer to the documentation https://docs.watchlog.io/?agent=Ubuntu."
        exit 0
    else
        echo "The Watchlog agent is installed but not currently running."
        echo "If you want to start it, use: systemctl start watchlog-agent"
        echo "If you want to update or remove the agent, please refer to the documentation https://docs.watchlog.io/?agent=Ubuntu."
        exit 0
    fi
fi

# Step 2: Check if Node.js is installed
if ! command -v node &> /dev/null; then
    echo "Node.js is not installed. Do you want to install it? (Y/N)"
    read install_node
    # Node.js installation via NodeSource (if user says Y)
    if [[ "$install_node" == "Y" || "$install_node" == "y" ]]; then
        echo "Installing Node.js globally..."
        curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
        if [ $? -ne 0 ]; then
            log_error "Failed to fetch Node.js setup script."
            exit 1
        fi
        sudo apt-get install -y nodejs
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
if [ -n "$UUID" ]; then
    echo "UUID=$UUID" | tee -a ./watchlog-agent/src/.env >/dev/null
else
    echo "UUID is not set, skipping .env update."
fi

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
