import telebot
from telebot import types
import subprocess
import time
from var_file import TOKEN, ALLOWED_USERS, DNS_URL_REFRESH, DDNS_TO_DIG, AUTHORITATIVE_DNS, IPTABLES_RULES

# Variables imported from 'var_file.py' file
# TOKEN                 ---> Set your Telegram bot token
# ALLOWED_USERS         ---> List of allowed Telegram user IDs 
# DNS_URL_REFRESH       ---> URL to update the IP 
# DDNS_TO_DIG           ---> DDNS domain with your public IP A record 
# AUTHORITATIVE_DNS     ---> If you don't want to wait 5 minutes... or just use 1.1.1.1
# IPTABLES_RULES        ---> IPTables rules to add IP to knockd whitelist

# Create a bot object
bot = telebot.TeleBot(TOKEN)

# Functions
def execute_ssh_command(command):
    status, output = subprocess.getstatusoutput(command)
    return output if status == 0 else f"Error: {output}"

def send_message_with_emoji_and_refresh(chat_id, text, emoji):
    markup = telebot.types.InlineKeyboardMarkup()
    refresh_button = telebot.types.InlineKeyboardButton(text='🔄 Refresh 🔄', callback_data='refresh')
    markup.add(refresh_button)
    bot.send_message(chat_id, f"{emoji} {text}", reply_markup=markup)

def send_inline_buttons(chat_id):
    global GUEST_IP
    buttons = [
        {'text': '📡 Update IP for door knocking', 'callback_data': 'share_ip'},
        {'text': f'✊🚪 Knock Door w/ {GUEST_IP if GUEST_IP else "<IP>"}', 'callback_data': 'knock_door'}
    ]
    markup = telebot.types.InlineKeyboardMarkup()
    for button in buttons:
        markup.add(telebot.types.InlineKeyboardButton(text=button['text'], callback_data=button['callback_data']))
    bot.send_message(chat_id, 'Click a button to perform an action:', reply_markup=markup)

def get_dig_ip():
    try:
        if subprocess.getstatusoutput("command -v nmcli")[0] == 0:
            dig_command = f"sudo /usr/bin/nmcli general reload dns-full && dig +short {DDNS_TO_DIG} {AUTHORITATIVE_DNS}"
        elif subprocess.getstatusoutput("command -v resolvectl")[0] == 0:
            dig_command = f"sudo /usr/bin/resolvectl flush-caches && dig +short {DDNS_TO_DIG} {AUTHORITATIVE_DNS}"
        else:
            print("No recognized network manager. This script is not compatible.")
            exit(5)

        status, output = subprocess.getstatusoutput(dig_command)
        if status == 0 and output:
            return output.strip()

    except Exception as e:
        print(e)
    return None

# Variable to store the guest IP
GUEST_IP = get_dig_ip()

# Handlers
@bot.message_handler(commands=['start', 'help'])
def send_welcome(message):
    user_id = message.from_user.id
    if user_id in ALLOWED_USERS:
        send_inline_buttons(message.chat.id)
    else:
        bot.send_message(message.chat.id, text='Unauthorized user.')

@bot.callback_query_handler(func=lambda call: True)
def handle_inline_buttons(call):
    global GUEST_IP
    user_id = call.from_user.id

    if user_id in ALLOWED_USERS:
        if call.data == 'share_ip':
            markup = telebot.types.InlineKeyboardMarkup()
            ip_button = telebot.types.InlineKeyboardButton(text='Share Public IP', url=DNS_URL_REFRESH)
            markup.add(ip_button)
            refresh_button = telebot.types.InlineKeyboardButton(text='🔄 Refresh 🔄', callback_data='refresh')
            markup.add(refresh_button)
            bot.send_message(call.message.chat.id, 'Click the link to share your IP:', reply_markup=markup)
        elif call.data == 'knock_door':
            bot.answer_callback_query(call.id, text='✊✊ Knock knock... Who\'s there? 🚪')
            time.sleep(1)
            ip = get_dig_ip()
            if ip:
                iptables_commands = IPTABLES_RULES
                iptables_commands = [cmd.format(ip=ip) for cmd in iptables_commands]
                iptables_commands = " && ".join(iptables_commands)
                iptables_output = execute_ssh_command(iptables_commands)
                if 'Error' not in iptables_output:
                    send_message_with_emoji_and_refresh(user_id, f"IP address {ip} added to whitelist.", '✅')
                else:
                    send_message_with_emoji_and_refresh(user_id, f"Error adding IP address {ip} to whitelist.", '❌')
            else:
                send_message_with_emoji_and_refresh(user_id, "Unable to get public IP address at the moment.", '❗️')
        elif call.data == 'refresh':
            GUEST_IP = get_dig_ip()
            send_inline_buttons(call.message.chat.id)

# Start the bot
bot.polling()
