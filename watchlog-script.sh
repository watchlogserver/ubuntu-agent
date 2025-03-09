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

# Use default memory if not provided (default 300M)
if [ -z "$MEMORY" ]; then
    MEMORY="300M"
fi

# Step 2: Check if Node.js is installed
if ! command -v node &> /dev/null; then
    echo "Node.js is not installed. Do you want to install it? (Y/N)"
    read install_node
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

# Step 3: Check if PM2 is installed, if not, install it globally
if ! command -v pm2 &> /dev/null; then
    echo "PM2 is not installed. Installing PM2 globally..."
    sudo npm install -g pm2
    if [ $? -ne 0 ]; then
        log_error "Failed to install PM2."
        exit 1
    fi
fi

# Step 4: Download the .deb package for Watchlog Agent
wget -O watchlog-agent.deb https://watchlog.io/ubuntu/watchlog-agent.deb >> $LOG_FILE 2>&1
if [ $? -ne 0 ]; then
    log_error "Failed to download the watchlog-agent package."
    exit 1
fi

# Extract the deb package contents
dpkg-deb -R ./watchlog-agent.deb watchlog-agent
if [ $? -ne 0 ]; then
    log_error "Failed to extract the watchlog-agent package."
    exit 1
fi

# Update the .env file with the provided variables
echo "WATCHLOG_APIKEY=$apiKey" | tee ./watchlog-agent/src/.env >/dev/null
echo "WATCHLOG_SERVER=$server" | tee -a ./watchlog-agent/src/.env >/dev/null
if [ -n "$UUID" ]; then
    echo "UUID=$UUID" | tee -a ./watchlog-agent/src/.env >/dev/null
else
    echo "UUID is not set, skipping .env update."
fi

# Copy the agent folder to /opt
sudo cp -R ./watchlog-agent /opt/watchlog-agent

# Step 5: Create a PM2 ecosystem configuration file
ECOSYSTEM_FILE="/opt/watchlog-agent/ecosystem.config.js"
sudo tee "$ECOSYSTEM_FILE" > /dev/null <<EOF
module.exports = {
  apps: [{
    name: 'watchlog-agent',
    script: 'watchlog-agent.js',
    cwd: '/opt/watchlog-agent/src',
    args: "\${process.env.WATCHLOG_APIKEY} \${process.env.WATCHLOG_SERVER} \${process.env.UUID}",
    max_memory_restart: process.env.MEMORY || "300M",
    env: {
      NODE_ENV: "production",
      WATCHLOG_APIKEY: "$apiKey",
      WATCHLOG_SERVER: "$server",
      UUID: "${UUID:-}"
    }
  }]
};
EOF

# Export MEMORY for PM2 if not already exported
export MEMORY

# Step 6: Start the agent with PM2
sudo pm2 start "$ECOSYSTEM_FILE"
if [ $? -ne 0 ]; then
    log_error "Failed to start the watchlog-agent with PM2."
    exit 1
fi

# Save PM2 process list so that it can restart on reboot
sudo pm2 save

echo "Watchlog agent installed and started successfully with PM2."
sudo rm watchlog_install.log
sudo rm -rf ./watchlog-agent
sudo rm watchlog-agent.deb
