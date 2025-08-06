#!/bin/bash

# ==============================================================================
# Skrip Instalasi Otomatis untuk Bot Telegram Konverter
# ==============================================================================

# Warna untuk output yang lebih baik
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Fungsi untuk menghentikan skrip jika terjadi kesalahan
trap 'echo -e "${YELLOW}Terjadi kesalahan. Instalasi dihentikan.${NC}"; exit 1' ERR
set -e

# --- Pemeriksaan Awal ---
echo -e "${BLUE}Memulai proses instalasi Bot Konverter Telegram...${NC}"

# Periksa apakah dijalankan sebagai root/sudo
if [ "$(id -u)" -ne 0 ]; then
  echo -e "${YELLOW}Skrip ini perlu dijalankan dengan hak akses root atau sudo.${NC}"
  echo "Silakan coba lagi dengan: sudo $0"
  exit 1
fi

# --- Meminta Informasi Pengguna ---
echo -e "${YELLOW}Harap masukkan informasi berikut:${NC}"
read -p "Masukkan Token Bot Telegram Anda: " BOT_TOKEN
read -p "Masukkan ID Telegram Anda yang diizinkan: " AUTHORIZED_USER_ID

if [ -z "$BOT_TOKEN" ] || [ -z "$AUTHORIZED_USER_ID" ]; then
    echo -e "${YELLOW}Token Bot dan ID Pengguna tidak boleh kosong. Instalasi dibatalkan.${NC}"
    exit 1
fi

# --- Instalasi Dependensi Sistem ---
echo -e "\n${BLUE}Langkah 1: Mengupdate sistem dan menginstal dependensi...${NC}"
apt-get update > /dev/null
apt-get install -y python3 python3-pip python3-venv > /dev/null
echo -e "${GREEN}Dependensi sistem berhasil diinstal.${NC}"

# --- Penyiapan Direktori dan Lingkungan Virtual ---
PROJECT_DIR="/opt/telegram_converter_bot"
VENV_DIR="$PROJECT_DIR/venv"

echo -e "\n${BLUE}Langkah 2: Menyiapkan direktori proyek di $PROJECT_DIR...${NC}"
mkdir -p $PROJECT_DIR
cd $PROJECT_DIR

echo -e "${BLUE}Langkah 3: Membuat lingkungan virtual Python...${NC}"
python3 -m venv $VENV_DIR
source $VENV_DIR/bin/activate

echo -e "${BLUE}Langkah 4: Menginstal library Python yang diperlukan...${NC}"
pip install python-telegram-bot > /dev/null
deactivate
echo -e "${GREEN}Library Python berhasil diinstal.${NC}"

# --- Membuat Skrip Bot Python ---
echo -e "\n${BLUE}Langkah 5: Membuat file skrip bot 'converter_bot.py'...${NC}"

cat << EOF > $PROJECT_DIR/converter_bot.py
import logging
import base64
import json
from urllib.parse import urlparse, parse_qs, unquote
from io import BytesIO

from telegram import Update, BotCommand
from telegram.ext import Application, CommandHandler, MessageHandler, filters, ContextTypes, ApplicationBuilder

# --- KONFIGURASI ---
BOT_TOKEN = "$BOT_TOKEN"
AUTHORIZED_USER_ID = $AUTHORIZED_USER_ID

logging.basicConfig(
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    level=logging.INFO
)
logger = logging.getLogger(__name__)
user_data = {}

def parse_vmess(uri: str) -> dict:
    decoded_str = base64.b64decode(uri[8:]).decode('utf-8')
    decoded = json.loads(decoded_str)
    proxy = {
        'name': decoded.get('ps', f"{decoded.get('add', '')}:{decoded.get('port', '')}"),'type': 'vmess',
        'server': decoded.get('add'),'port': int(decoded.get('port')),'uuid': decoded.get('id'),
        'alterId': decoded.get('aid', 0),'cipher': decoded.get('scy', 'auto'),
        'tls': decoded.get('tls') == 'tls','network': decoded.get('net', 'tcp'),
    }
    if proxy['tls']: proxy['sni'] = decoded.get('sni') or decoded.get('host') or decoded.get('add')
    if proxy['network'] == 'ws':
        proxy['ws-opts'] = {'path': decoded.get('path', '/'), 'headers': {'Host': decoded.get('host') or decoded.get('add')}}
    return proxy

def parse_vless(uri: str) -> dict:
    url = urlparse(uri); params = parse_qs(url.query)
    proxy = {
        'name': unquote(url.fragment) if url.fragment else f"{url.hostname}:{url.port}",'type': 'vless',
        'server': url.hostname,'port': url.port,'uuid': url.username,
        'tls': params.get('security', [''])[0] == 'tls','network': params.get('type', ['tcp'])[0],
        'flow': params.get('flow', [''])[0]
    }
    if proxy['tls']: proxy['sni'] = params.get('sni', [url.hostname])[0]
    if proxy['network'] == 'ws':
        proxy['ws-opts'] = {'path': params.get('path', ['/'])[0], 'headers': {'Host': params.get('host', [url.hostname])[0]}}
    if proxy['network'] == 'grpc': proxy['grpc-opts'] = {'grpc-service-name': params.get('serviceName', [''])[0]}
    return proxy

def parse_trojan(uri: str) -> dict:
    url = urlparse(uri); params = parse_qs(url.query)
    proxy = {
        'name': unquote(url.fragment) if url.fragment else f"{url.hostname}:{url.port}",'type': 'trojan',
        'server': url.hostname,'port': url.port,'password': url.username,'tls': True,
        'sni': params.get('sni', [url.hostname])[0],'network': params.get('type', ['tcp'])[0],
    }
    if proxy['network'] == 'ws':
        proxy['ws-opts'] = {'path': params.get('path', ['/'])[0], 'headers': {'Host': params.get('host', [url.hostname])[0]}}
    if proxy['network'] == 'grpc': proxy['grpc-opts'] = {'grpc-service-name': params.get('serviceName', [''])[0]}
    return proxy

def generate_yaml(proxies: list) -> str:
    yaml_string = 'proxies:\\n'
    for p in proxies:
        yaml_string += f'  - name: "{p["name"]}"\\n'; yaml_string += f'    type: {p["type"]}\\n'
        yaml_string += f'    server: {p["server"]}\\n'; yaml_string += f'    port: {p["port"]}\\n'
        if p.get('uuid'): yaml_string += f'    uuid: {p["uuid"]}\\n'
        if p.get('password'): yaml_string += f'    password: {p["password"]}\\n'
        if p['type'] == 'vmess':
            yaml_string += f'    alterId: {p["alterId"]}\\n'; yaml_string += f'    cipher: {p["cipher"]}\\n'
        if p.get('tls'): yaml_string += f'    tls: true\\n'
        if p.get('sni'): yaml_string += f'    sni: {p["sni"]}\\n'
        if p.get('network') and p['network'] != 'tcp': yaml_string += f'    network: {p["network"]}\\n'
        if p.get('flow'): yaml_string += f'    flow: {p["flow"]}\\n'
        if p.get('ws-opts'):
            yaml_string += '    ws-opts:\\n'; yaml_string += f'      path: "{p["ws-opts"]["path"]}"\\n'
            if p['ws-opts'].get('headers', {}).get('Host'):
                yaml_string += '      headers:\\n'; yaml_string += f'        Host: {p["ws-opts"]["headers"]["Host"]}\\n'
        if p.get('grpc-opts'):
            yaml_string += '    grpc-opts:\\n'; yaml_string += f'      grpc-service-name: "{p["grpc-opts"]["grpc-service-name"]}"\\n'
    return yaml_string

async def start_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if update.effective_user.id != AUTHORIZED_USER_ID:
        await update.message.reply_text("Maaf, Anda tidak diizinkan menggunakan bot ini."); return
    user_data.setdefault(update.effective_user.id, {})['bug_host'] = ''
    welcome_message = "👋 **Selamat Datang!**\\n\\n/setbug host.com - Atur Bug Host\\n/clearbug - Hapus Bug Host\\n\\nKirim link akun untuk konversi."
    await update.message.reply_text(welcome_message, parse_mode='Markdown')

async def set_bug_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if update.effective_user.id != AUTHORIZED_USER_ID: return
    if not context.args: await update.message.reply_text("Gunakan: /setbug bug.host.com"); return
    bug_host = context.args[0]; user_data.setdefault(update.effective_user.id, {})['bug_host'] = bug_host
    await update.message.reply_text(f"✅ Bug Host diatur ke: `{bug_host}`", parse_mode='Markdown')

async def clear_bug_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if update.effective_user.id != AUTHORIZED_USER_ID: return
    user_data.setdefault(update.effective_user.id, {})['bug_host'] = ''
    await update.message.reply_text("🗑️ Bug Host telah dihapus.")

async def handle_text_message(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if update.effective_user.id != AUTHORIZED_USER_ID: return
    bug_host = user_data.get(update.effective_user.id, {}).get('bug_host', '')
    uris = update.message.text.strip().split('\\n'); proxies = []
    await update.message.reply_text("Memproses...")
    for uri in uris:
        uri = uri.strip(); proxy = None
        if not uri: continue
        try:
            if uri.startswith('vmess://'): proxy = parse_vmess(uri)
            elif uri.startswith('vless://'): proxy = parse_vless(uri)
            elif uri.startswith('trojan://'): proxy = parse_trojan(uri)
            if proxy:
                if bug_host: proxy['server'] = bug_host
                proxies.append(proxy)
        except Exception as e: logger.warning(f"Gagal proses URI: {uri[:30]}... | Error: {e}")
    if not proxies: await update.message.reply_text("Gagal. Tidak ada link valid."); return
    yaml_content = generate_yaml(proxies)
    yaml_file = BytesIO(yaml_content.encode('utf-8')); yaml_file.name = 'config.yaml'
    caption = f"✅ Berhasil mengonversi {len(proxies)} akun."
    if bug_host: caption += f"\\n🐞 Bug Host aktif: `{bug_host}`"
    await update.message.reply_document(document=yaml_file, caption=caption, parse_mode='Markdown')

async def post_init(application: Application):
    await application.bot.set_my_commands([
        BotCommand("start", "Memulai bot"),
        BotCommand("setbug", "Mengatur Bug Host"),
        BotCommand("clearbug", "Menghapus Bug Host"),
    ])

def main():
    logger.info("Mulai menjalankan bot..."); application = ApplicationBuilder().token(BOT_TOKEN).post_init(post_init).build()
    application.add_handler(CommandHandler("start", start_command))
    application.add_handler(CommandHandler("setbug", set_bug_command))
    application.add_handler(CommandHandler("clearbug", clear_bug_command))
    application.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_text_message))
    application.run_polling()
    
if __name__ == '__main__': main()
EOF

echo -e "${GREEN}File skrip bot berhasil dibuat.${NC}"

# --- Membuat Service systemd ---
echo -e "\n${BLUE}Langkah 6: Membuat service systemd 'converterbot.service'...${NC}"
SERVICE_FILE="/etc/systemd/system/converterbot.service"

# Dapatkan username, bahkan jika dijalankan dengan sudo
CURRENT_USER=${SUDO_USER:-$(whoami)}
USER_HOME=$(eval echo ~$CURRENT_USER)

cat << EOF > $SERVICE_FILE
[Unit]
Description=Telegram Converter Bot
After=network.target

[Service]
User=$CURRENT_USER
Group=nogroup
WorkingDirectory=$PROJECT_DIR
ExecStart=$VENV_DIR/bin/python $PROJECT_DIR/converter_bot.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

echo -e "${GREEN}File service systemd berhasil dibuat.${NC}"

# --- Menjalankan Service ---
echo -e "\n${BLUE}Langkah 7: Menjalankan dan mengaktifkan service bot...${NC}"
systemctl daemon-reload
systemctl enable converterbot.service > /dev/null
systemctl start converterbot.service

# Beri sedikit waktu untuk service berjalan sebelum cek status
sleep 3

# --- Verifikasi ---
echo -e "\n${GREEN}--- INSTALASI SELESAI ---${NC}"
echo -e "Bot Anda sekarang seharusnya sudah berjalan 24/7."
echo -e "Berikut adalah status service saat ini:"
systemctl status converterbot.service --no-pager
echo -e "\n${YELLOW}Jika status tidak 'active (running)', gunakan 'sudo journalctl -u converterbot.service -f' untuk melihat log error.${NC}"
echo -e "${BLUE}Anda sekarang bisa membuka Telegram dan berinteraksi dengan bot Anda.${NC}"