#!/bin/bash
if command -v whiptail > /dev/null;
then
    whiptail --title "Welcome" --yes-button "Continue" --no-button "Exit" --yesno "This script will install the required components for the Telegram bot to function." 10 60 || exit 34
else
    echo -e "\n\n\nThis script will install the required components for the Telegram bot to function.\nPress ENTER to continue or CTRL+C to exit.\n"
    read
fi

if [[ -e "/run/systemd/system" || -e "/usr/lib/systemd/system" ]]; then
    echo "System uses systemd" > /dev/null
else
    echo "System does not use systemd. This script is incompatible."
    exit 88
fi

# Determine if the system uses dnf or apt-get
PKG_MANAGER=$( command -v dnf || command -v apt-get ) || { echo "Neither dnf nor apt-get detected. This script is incompatible."; exit 99; }

# Execute pre-checks and installation operations
if ! {
    # Check for root user
    if [ "$EUID" -eq 0 ]; then
        echo "You are logged in as root. Execute the script as a standard user with sudo privileges."
        exit 10
    fi

    # Verify that the current user has sudo privileges
    sudo -l -U $USER >/dev/null 2>&1 || { echo "The user lacks sudo privileges"; exit 5; }
    sudo systemctl list-units >/dev/null 2>&1 || { echo "The user lacks sudo privileges"; exit 5; }

    # Prevent interactive mode for iptables-persistent installation
    if [[ ! "$PKG_MANAGER" =~ "dnf" ]]; then
    sudo debconf-set-selections <<00000000EOT
        iptables-persistent iptables-persistent/autosave_v4 boolean true
        iptables-persistent iptables-persistent/autosave_v6 boolean true
00000000EOT
    fi

    # Install necessary packages with apt or dnf
    if [[ ! "$PKG_MANAGER" =~ "dnf" ]]; then
        sudo apt update 
        sudo NEEDRESTART_SUSPEND=1 apt install whiptail sed gawk iptables iptables-persistent python3 python3-pip dnsutils -y
        # APT
        sudo dpkg -s dnsutils gawk whiptail iptables sed iptables-persistent python3 python3-pip &> /dev/null || {
            whiptail --title "Error" --msgbox "Error during package installation." 10 50
            exit 19
        }
    else
        sudo dnf update -y
        sudo dnf install newt sed gawk iptables iptables-services python3 python3-pip bind-utils -y
        # DNF
        missing_packages=()
        for pkg in newt sed gawk iptables-nft python3 python3-pip bind-utils 
        do
            if ! sudo dnf list installed "$pkg" > /dev/null 2>&1; then
                missing_packages+=("$pkg")
            fi
        done
        if [ ${#missing_packages[@]} -gt 0 ]; then
            missing_packages_list=$(IFS=', '; echo "${missing_packages[*]}")
            whiptail --title "Error" --msgbox "The following packages were not installed: $missing_packages_list\n\nPlease try again..." 15 50
            exit 19
        fi
    fi

    # Install "pyTelegramBotAPI" using pip/pip3
    if command -v pip3 &>/dev/null; then
        pip3 install pyTelegramBotAPI --break-system-packages
        if [ $? -ne 0 ]; then
            pip3 install pyTelegramBotAPI
        fi
        pip3 show pyTelegramBotAPI &> /dev/null || { 
        whiptail --title "Error" --msgbox "pyTelegramBotAPI was not installed." 10 50
        exit 19
    }
    else
        pip install pyTelegramBotAPI --break-system-packages
        if [ $? -ne 0 ]; then
            pip install pyTelegramBotAPI
        fi
        pip show pyTelegramBotAPI &> /dev/null || { 
        whiptail --title "Error" --msgbox "pyTelegramBotAPI was not installed." 10 50
        exit 19
    }
    fi

    # Create a group that allows SUDO usage without a password for specific commands
    sudo groupadd telegrambot
    sudo usermod -aG telegrambot $(whoami)

    # Grant NOPASSWD for specific commands to the telegrambot group
    sudo bash -c 'echo "%telegrambot ALL=(ALL) NOPASSWD: /sbin/iptables,/usr/bin/resolvectl,/usr/sbin/iptables-save,/usr/bin/nmcli" > /etc/sudoers.d/66-telegram-bot'

    # Check network manager
    if [ -x "$(command -v nmcli)" ]; then
        echo "NetworkManager is active." > /dev/null
        if ! sudo -n /sbin/iptables -L &>/dev/null || ! sudo -n /usr/bin/nmcli &>/dev/null; then 
            whiptail --title "Error" --msgbox "Error setting up sudo permissions." 10 50
            exit 22
        fi
    elif [ -x "$(command -v resolvectl)" ]; then
        echo "resolvectl is active." > /dev/null
         # Confirm sudoers permissions
        if ! sudo -n /sbin/iptables -L &>/dev/null || ! sudo -n /usr/bin/resolvectl &>/dev/null; then 
            whiptail --title "Error" --msgbox "Error setting up sudo permissions." 10 50
            exit 23
        fi
    else
        echo "No recognized network manager detected. This script is incompatible."
        exit 18
    fi
    
}; then
    # Display error message
    whiptail --title "Error" --msgbox "An error occurred during the pre-check or installation." 10 50
    exit 1
fi

# Display completion message
whiptail --title "Completed" --msgbox "Installation and pre-check were completed successfully!" 10 50

# Prompt user to proceed with guided entry of whitelisted ports
whiptail --title "Whitelist Ports" --yesno \
"Do you wish to continue with the guided entry of whitelisted ports?\n\nNote: This action will overwrite any existing iptables rules." 15 60

# Store exit status
choice=$?

if [ $choice -eq 0 ]; 
then
    # Begin port entry
    # Create file header and remove if a previous version exists
    echo "PORT|PROTOCOL" > ./ports-tmp.csv

    # Function to add a port
    add_port() {
        # Prompt user for port number
        PORT=$(whiptail --inputbox "Enter the port number (1-65535)" 8 50 "" --title "Port Number" 3>&1 1>&2 2>&3)

        # Exit if user cancels
        exitstatus=$?
        if [ $exitstatus != 0 ]; then
            return
        fi

        # Prompt user for protocol type (TCP or UDP)
        PROTOCOL=$(whiptail --title "Protocol Type" --nocancel --menu "Choose the protocol type:" 12 38 2 "TCP" "" "UDP" "" 3>&1 1>&2 2>&3)

        # Exit if user cancels
        exitstatus=$?
        if [ $exitstatus != 0 ]; then
            return
        fi

        # Record details to CSV file
        echo "$PORT|${PROTOCOL,,}" >> ./ports-tmp.csv
    }

    remove_port() {
        # Read CSV file to display available ports
        PORTS=$(awk -F '|' 'NR>1 {printf "%s %s\n", $1, $2}' ./ports-tmp.csv)

        # Prompt user to choose a port to remove
        SELECTION=$(whiptail --title "Remove Port" --menu "Select a port to remove" 15 50 6 ${PORTS} 3>&1 1>&2 2>&3)

        # Exit if user cancels
        exitstatus=$?
        if [ $exitstatus != 0 ]; then
            return
        fi

        # Remove the corresponding line for the chosen port
        sed -i "/^${SELECTION}|/d" ./ports-tmp.csv
    }

    while true; do
        # Prompt user to add a port, remove a port, view added ports, or exit
        CHOICE=$(whiptail --title "Menu" --menu "Select an option" 15 55 5 \
        "Add a port" "" \
        "Remove port" "" \
        "View added ports" "" \
        "Complete Selection" "" --nocancel 3>&1 1>&2 2>&3)

        # Exit if user cancels
        exitstatus=$?
        if [ $exitstatus != 0 ]; then
            break
        fi

        case $CHOICE in
            "Add a port") add_port ;;
            "Remove port") remove_port ;;
            "View added ports")
                PORTS=$(awk -F '|' '{printf "%-10s\t%s\n", $1, $2}' ./ports-tmp.csv)
                whiptail --title "Added Ports" --msgbox "$PORTS" 15 40
                ;;
            "Complete Selection") 
                if [ `cat ./ports-tmp.csv|wc -l` -lt "2" ]; 
                then
                    if whiptail --title "Confirmation" --yesno "No ports were added. Are you sure you want to exit?" 10 40; 
                    then
                        rm -f ./ports-tmp.csv
                        exit 1
                    fi
                else
                    break
                fi
                ;;
        esac
    done

    # Activate iptables and, for Debian, activate netfilter
    if [[ ! "$PKG_MANAGER" =~ "dnf" ]]; then
        sudo /usr/bin/systemctl enable netfilter-persistent.service
    else
        sudo systemctl enable iptables
        sudo systemctl start iptables
    fi

    # Create and apply iptables rules
    RULES_COMMANDS=""
    # Read file and create iptables commands for DROP and ACCEPT
    while IFS='|' read -r PORT PROTOCOL; do
        ACCEPT_COMMAND="sudo /sbin/iptables -A INPUT -p $PROTOCOL -s 192.168.0.0/16 --dport $PORT -j ACCEPT"
        ACCEPT_COMMAND+="\nsudo /sbin/iptables -A INPUT -p $PROTOCOL -s 172.16.0.0/12 --dport $PORT -j ACCEPT"
        ACCEPT_COMMAND+="\nsudo /sbin/iptables -A INPUT -p $PROTOCOL -s 10.0.0.0/8 --dport $PORT -j ACCEPT"
        DROP_COMMAND="sudo /sbin/iptables -A INPUT -p $PROTOCOL --dport $PORT -j DROP"
        RULES_COMMANDS+="\n$ACCEPT_COMMAND\n$DROP_COMMAND"
    done < <(tail -n +2 ./ports-tmp.csv)

    echo 'sudo /sbin/iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT' > ./iptables-rules.tmp
    echo -e "$RULES_COMMANDS" >> ./iptables-rules.tmp
    source ./iptables-rules.tmp

    if [[ ! "$PKG_MANAGER" =~ "dnf" ]]; then
        # Store iptables settings to ensure they persist after a reboot
        sudo sh -c '/usr/sbin/iptables-save > /etc/iptables/rules.v4'
    else
        sudo service iptables save
    fi

    # Append rules to the Python configuration file
    VAR_FILE="./var_file.py"

    echo -e "\nIPTABLES_RULES = [" >> "$VAR_FILE"

    while IFS='|' read -r port protocol; do
        rule="    \"sudo /sbin/iptables -I INPUT 1 -s {ip} -p $protocol --dport $port -j ACCEPT\""
        echo "$rule," >> "$VAR_FILE"
    done < <(tail -n +2 ./ports-tmp.csv)

    # Remove the comma from the last line
    sed -i '$ s/,$//' "$VAR_FILE"

    # End of rule list and remove iptables-rules.tmp and ports-tmp.csv files
    echo "]" >> "$VAR_FILE"
    rm -f ./iptables-rules.tmp
    rm -f ./ports-tmp.csv
else
    exit 55
fi

# Ask if the user wants to set up the Telegram BOT and DDNS information
if whiptail --title "Configuration" --yesno "Would you like to set up the Telegram BOT and DDNS information now?" 10 40; then
    # Prompt for Telegram BOT token
    TOKEN=$(whiptail --title "Configuration" --inputbox "Enter your Telegram BOT token:\n\ne.g. 0000000000:xyxyxyxyxyxyyxyxyxyxyxyxyxyxyxyxyxy" 13 55 --title "Telegram BOT Token" --cancel-button "Add Later" 3>&1 1>&2 2>&3)
    if [ -n "$TOKEN" ]; then
        echo "TOKEN = '$TOKEN'" >> "$VAR_FILE"
    fi

    # Prompt for Telegram authorized users
    ALLOWED_USERS=$(whiptail --title "Configuration" --inputbox "Enter Telegram user IDs separated by commas:\n\ne.g. 123456789,987654321" 13 55 --title "Authorized Telegram Users" --cancel-button "Add Later" 3>&1 1>&2 2>&3)
    if [ -n "$ALLOWED_USERS" ]; then
        echo "ALLOWED_USERS = [$ALLOWED_USERS]" >> "$VAR_FILE"
    fi

    # Prompt for DDNS domain
    DDNS_TO_DIG=$(whiptail --title "Configuration" --inputbox "Enter your DDNS domain:\n\ne.g. my-domain.duckdns.org" 13 55 --title "DDNS Domain" --cancel-button "Add Later" 3>&1 1>&2 2>&3)
    if [ -n "$DDNS_TO_DIG" ]; then
        echo "DDNS_TO_DIG = '$DDNS_TO_DIG'" >> "$VAR_FILE"
    fi

    # Prompt for DNS update URL
    DNS_URL_REFRESH=$(whiptail --title "Configuration" --inputbox "Enter the URL to refresh your DDNS:\n\ne.g. https://www.duckdns.org/update<MY_DOMAIN><DUCKDNS_TOKEN>" 13 75 --title "DDNS Update URL" --cancel-button "Add Later" 3>&1 1>&2 2>&3)
    if [ -n "$DNS_URL_REFRESH" ]; then
        echo "DNS_URL_REFRESH = '$DNS_URL_REFRESH'" >> "$VAR_FILE"
    fi

    # Prompt for authoritative DNS
    AUTHORITATIVE_DNS=$(whiptail --title "Configuration" --inputbox "Enter the authoritative DNS (default: 1.1.1.1):" 10 55 "1.1.1.1" --title "Authoritative DNS" --cancel-button "Add Later" 3>&1 1>&2 2>&3)
    if [ -n "$AUTHORITATIVE_DNS" ]; then
        echo "AUTHORITATIVE_DNS = '@$AUTHORITATIVE_DNS'" >> "$VAR_FILE"
    fi
fi

whiptail --title "Script Configuration" --msgbox "You can now launch the Python script using the following command:\n\npython3 main.py" 10 70
