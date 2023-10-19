# TGknock-bot

TGknock-bot is a Telegram bot utility designed as a modern and more convenient alternative to the traditional terminal-based door knocking technique. By leveraging Telegram as the interface, users can update IP addresses and execute door knocking remotely with ease, all within the familiar environment of a chat app.

## Table of Contents
- [Features](#features)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Interacting with the Telegram Bot](#interacting-with-the-telegram-bot)
- [Manual Configuration](#manual-configuration)
- [Running TGknock-bot as a Systemd Service](#running-tgknock-bot-as-a-systemd-service)
  
## Features

- **Secure Access**: Only whitelisted Telegram IDs can interact with and control the bot.
- **DDNS Integration**: Works with public DDNS providers like DuckDNS, No-IP, and more.
- **Easy IP Refresh**: Directly refresh your DDNS URL through Telegram.
- **Automated IP Whitelisting**: Dynamically add IPs to your server's whitelist.
- **Convenience**: Eliminate the need for terminal-based door knocking and use the friendly Telegram interface instead.

## Prerequisites

- Python 3.x
- A Telegram account
- A public DDNS (like DuckDNS, No-IP, etc.)
  
## Quick Start

1. Clone the repository:

```bash
git clone https://github.com/rempairamore/TGknock-bot.git
```

2. Navigate into the cloned directory:

```bash
cd TGknock-bot
```

3. Use the provided setup script for guided configuration:

```bash
bash script_setup.sh
```

This will guide you through the necessary steps, including setting up the `var_file.py` from the provided `var_file.py_example`.

4. Start the bot:

```bash
python3 main_script.py
```

## Interacting with the Telegram Bot

To interact with the Telegram bot, follow these steps:

1. **Opening Telegram**: Launch the Telegram application on your device.
2. **Accessing the Bot**: Search for and access the bot you've configured.
3. **Starting the Bot**: Initiate the conversation with the bot (/start).
4. You'll be presented with the message:
   > "Click a button to perform an action:"
   
5. **Updating Your IP Address**:
   - Click on the "Update IP for door knocking" button.
   - Next, click on "Share public IP". This will open a new browser page to update the DDNS with your IP address.
   - Return to your Telegram bot and click on "Refresh".
   
6. **Performing the Knock**:
   - Click on "Knock Door w/<your_IP>".
   - Wait for the bot's response. After a few seconds, the bot will correctly open the previously configured ports.


<a href="https://i.imgur.com/ZLFqkTl.png">
    <img src="https://i.imgur.com/ZLFqkTl.png" alt="TELEGRAM BOT" width=50%/>
</a>

## Manual Configuration

Before running the script, you'll need to configure some variables in the `var_file.py` (use the `var_file.py_example` as a template). You can either manually edit this file or use the provided `script_setup.sh` for a guided configuration.

Here's a brief overview of the variables:

- `TOKEN`: Your Telegram bot token.
- `ALLOWED_USERS`: List of Telegram IDs allowed to interact with the bot.
- `DDNS_TO_DIG`: Your public DDNS.
- `DNS_URL_REFRESH`: URL that refreshes your DDNS IP address.
- `AUTHORITATIVE_DNS`: The authoritative DNS of your DDNS domain for almost immediate IP updates.
- `IPTABLES_RULES`: Ports that the server will open for the whitelisted IP.

Ensure you replace placeholders in `var_file.py` with actual values.

## Running TGknock-bot as a Systemd Service

Systemd is a system and session manager for Linux, which allows you to manage and configure services. By setting up TGknock-bot as a systemd service, you can ensure that the bot automatically starts every time your server boots.

### Creating the Systemd Service

1. Create a systemd service file for TGknock-bot:

```bash
sudo nano /etc/systemd/system/tgknock-bot.service
```

2. Paste the following configuration into the editor:

```
[Unit]
Description=TGknock-bot Service
After=network.target

[Service]
Type=simple
WorkingDirectory=/path/to/TGknock-bot
ExecStart=/usr/bin/python3 /path/to/TGknock-bot/main_script.py
Restart=on-failure
User=YOUR_USERNAME
Group=YOUR_GROUP

[Install]
WantedBy=multi-user.target
```

Replace `/path/to/TGknock-bot` with the absolute path to the TGknock-bot directory. Also, replace `YOUR_USERNAME` and `YOUR_GROUP` with the username and group under which you want to run the bot.

3. Reload the systemd manager configuration:

```bash
sudo systemctl daemon-reload
```

4. Start the TGknock-bot service:

```bash
sudo systemctl start tgknock-bot
```

5. Optionally, enable the TGknock-bot service to start on boot:

```bash
sudo systemctl enable tgknock-bot
```

### Checking the Service Status

To monitor the service's status, use:

```bash
sudo systemctl status tgknock-bot
```

## Tested Environments

This script has been tested on the following operating systems:

- Debian 11
- Debian 12
- Ubuntu 20.04
- Ubuntu 22.04
- Amazon Linux 2023
- Red Hat Enterprise Linux 9
