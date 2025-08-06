#!/bin/bash

# ==============================================================================
# Skrip Instalasi, Manajemen, & Update Otomatis untuk Bot Telegram Konverter
# Versi 3.0
# ==============================================================================

# --- Konfigurasi & Variabel Global ---
PROJECT_DIR="/opt/telegram_converter_bot"
SERVICE_FILE="/etc/systemd/system/converterbot.service"
BOT_SCRIPT_PATH="$PROJECT_DIR/converter_bot.py"
VENV_DIR="$PROJECT_DIR/venv"
MENU_SCRIPT_PATH="/usr/local/bin/m-yaml"
HELPER_SCRIPT_PATH="$PROJECT_DIR/bot_helpers.sh"
# URL GitHub Anda untuk fungsi update
GITHUB_SCRIPT_URL="https://raw.githubusercontent.com/angga2103/autoscript-vip/main/konvert-yaml.sh"

# Warna untuk output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# --- Fungsi-fungsi Pembantu ---

# Fungsi untuk menghentikan skrip jika terjadi kesalahan
trap 'echo -e "${YELLOW}Terjadi kesalahan. Proses dihentikan.${NC}"; exit 1' ERR
set -e

# Fungsi untuk meminta kredensial dan membuat skrip bot
function create_bot_script() {
    echo -e "${YELLOW}Harap masukkan informasi bot Anda:${NC}"
    read -p "Masukkan Token Bot Telegram baru: " BOT_TOKEN
    read -p "Masukkan ID Telegram Anda yang diizinkan: " AUTHORIZED_USER_ID

    if [ -z "$BOT_TOKEN" ] || [ -z "$AUTHORIZED_USER_ID" ]; then
        echo -e "${YELLOW}Token Bot dan ID Pengguna tidak boleh kosong. Proses dibatalkan.${NC}"
        exit 1
    fi

    echo -e "${BLUE}Membuat file skrip bot di '$BOT_SCRIPT_PATH'...${NC}"
    cat << EOF > "$BOT_SCRIPT_PATH"
import logging, base64, json
from urllib.parse import urlparse, parse_qs, unquote
from telegram import Update, BotCommand
from telegram.ext import Application, CommandHandler, MessageHandler, filters, ContextTypes, ApplicationBuilder

# --- KONFIGURASI ---
BOT_TOKEN = "$BOT_TOKEN"
AUTHORIZED_USER_ID = $AUTHORIZED_USER_ID

logging.basicConfig(format='%(asctime)s - %(name)s - %(levelname)s - %(message)s', level=logging.INFO)
logger = logging.getLogger(__name__)
user_data = {}

# --- FUNGSI PARSER (Tetap sama) ---
def parse_vmess(uri: str) -> dict:
    decoded_str = base64.b64decode(uri[8:]).decode('utf-8'); decoded = json.loads(decoded_str)
    proxy = {'name': decoded.get('ps', f"{decoded.get('add', '')}:{decoded.get('port', '')}"),'type': 'vmess','server': decoded.get('add'),'port': int(decoded.get('port')),'uuid': decoded.get('id'),'alterId': decoded.get('aid', 0),'cipher': decoded.get('scy', 'auto'),'tls': decoded.get('tls') == 'tls','network': decoded.get('net', 'tcp')}
    if proxy['tls']: proxy['sni'] = decoded.get('sni') or decoded.get('host') or decoded.get('add')
    if proxy['network'] == 'ws': proxy['ws-opts'] = {'path': decoded.get('path', '/'), 'headers': {'Host': decoded.get('host') or decoded.get('add')}}
    return proxy
def parse_vless(uri: str) -> dict:
    url = urlparse(uri); params = parse_qs(url.query)
    proxy = {'name': unquote(url.fragment) if url.fragment else f"{url.hostname}:{url.port}",'type': 'vless','server': url.hostname,'port': url.port,'uuid': url.username,'tls': params.get('security', [''])[0] == 'tls','network': params.get('type', ['tcp'])[0],'flow': params.get('flow', [''])[0]}
    if proxy['tls']: proxy['sni'] = params.get('sni', [url.hostname])[0]
    if proxy['network'] == 'ws': proxy['ws-opts'] = {'path': params.get('path', ['/'])[0], 'headers': {'Host': params.get('host', [url.hostname])[0]}}
    if proxy['network'] == 'grpc': proxy['grpc-opts'] = {'grpc-service-name': params.get('serviceName', [''])[0]}
    return proxy
def parse_trojan(uri: str) -> dict:
    url = urlparse(uri); params = parse_qs(url.query)
    proxy = {'name': unquote(url.fragment) if url.fragment else f"{url.hostname}:{url.port}",'type': 'trojan','server': url.hostname,'port': url.port,'password': url.username,'tls': True,'sni': params.get('sni', [url.hostname])[0],'network': params.get('type', ['tcp'])[0]}
    if proxy['network'] == 'ws': proxy['ws-opts'] = {'path': params.get('path', ['/'])[0], 'headers': {'Host': params.get('host', [url.hostname])[0]}}
    if proxy['network'] == 'grpc': proxy['grpc-opts'] = {'grpc-service-name': params.get('serviceName', [''])[0]}
    return proxy

# --- FUNGSI GENERATOR YAML (Tetap sama) ---
def generate_yaml(proxies: list) -> str:
    yaml_string = 'proxies:\\n'
    for p in proxies:
        yaml_string += f'  - name: "{p["name"]}"\\n'; yaml_string += f'    type: {p["type"]}\\n'; yaml_string += f'    server: {p["server"]}\\n'; yaml_string += f'    port: {p["port"]}\\n'
        if p.get('uuid'): yaml_string += f'    uuid: {p["uuid"]}\\n'
        if p.get('password'): yaml_string += f'    password: {p["password"]}\\n'
        if p['type'] == 'vmess': yaml_string += f'    alterId: {p["alterId"]}\\n'; yaml_string += f'    cipher: {p["cipher"]}\\n'
        if p.get('tls'): yaml_string += f'    tls: true\\n'
        if p.get('sni'): yaml_string += f'    sni: {p["sni"]}\\n'
        if p.get('network') and p['network'] != 'tcp': yaml_string += f'    network: {p["network"]}\\n'
        if p.get('flow'): yaml_string += f'    flow: {p["flow"]}\\n'
        if p.get('ws-opts'): yaml_string += '    ws-opts:\\n'; yaml_string += f'      path: "{p["ws-opts"]["path"]}"\\n';
        if p.get('ws-opts', {}).get('headers', {}).get('Host'): yaml_string += f'      headers:\\n        Host: {p["ws-opts"]["headers"]["Host"]}\\n'
        if p.get('grpc-opts'): yaml_string += '    grpc-opts:\\n'; yaml_string += f'      grpc-service-name: "{p["grpc-opts"]["grpc-service-name"]}"\\n'
    return yaml_string

# --- HANDLER BOT (Diperbarui) ---
async def start_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if update.effective_user.id != AUTHORIZED_USER_ID: await update.message.reply_text("Maaf, Anda tidak diizinkan."); return
    user_data.setdefault(update.effective_user.id, {})['bug_host'] = ''
    await update.message.reply_text("👋 **Selamat Datang!**\\n\\n/setbug host.com - Atur Bug Host\\n/clearbug - Hapus Bug Host\\n\\nKirim link untuk konversi.", parse_mode='Markdown')
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
    
    # --- PERUBAHAN UTAMA DI SINI ---
    yaml_content = generate_yaml(proxies)
    # Format output menjadi teks monospace
    header = f"✅ Berhasil mengonversi {len(proxies)} akun."
    if bug_host: header += f"\\n🐞 Bug Host aktif: {bug_host}"
    
    # Kirim sebagai pesan teks dengan format code block
    message_text = f"{header}\\n\\n```yaml\\n{yaml_content}```"
    await update.message.reply_text(message_text, parse_mode='MarkdownV2')

async def post_init(application: Application):
    await application.bot.set_my_commands([
        BotCommand("start", "Memulai bot"), BotCommand("setbug", "Mengatur Bug Host"),
        BotCommand("clearbug", "Menghapus Bug Host"),
    ])

def main():
    logger.info("Mulai menjalankan bot..."); application = ApplicationBuilder().token(BOT_TOKEN).post_init(post_init).build()
    application.add_handler(CommandHandler("start", start_command)); application.add_handler(CommandHandler("setbug", set_bug_command))
    application.add_handler(CommandHandler("clearbug", clear_bug_command)); application.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_text_message))
    application.run_polling()
if __name__ == '__main__': main()
EOF
    echo -e "${GREEN}File skrip bot berhasil dibuat/diperbarui.${NC}"
}

# Fungsi untuk membuat skrip menu manajemen
function create_menu_script() {
    echo -e "${BLUE}Membuat perintah manajemen 'm-yaml'...${NC}"
    # Membuat skrip menu
    cat << EOF > "$MENU_SCRIPT_PATH"
#!/bin/bash
# Skrip menu untuk mengelola bot konverter

# Warna
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Path ke file helper dan URL update
HELPER_SCRIPT="$HELPER_SCRIPT_PATH"
UPDATE_URL="$GITHUB_SCRIPT_URL"

function show_menu() {
    clear
    echo -e "${BLUE}=========================================${NC}"
    echo -e "${GREEN}  Manajemen Bot Konverter YAML${NC}"
    echo -e "${BLUE}=========================================${NC}"
    echo "1. Edit Bot (Ganti Token & ID)"
    echo "2. Restart Bot"
    echo "3. Cek Status Bot"
    echo "4. Cek Log Bot"
    echo "5. Update Skrip Bot"
    echo "6. Keluar"
    echo -e "${BLUE}-----------------------------------------${NC}"
}

function edit_bot() {
    echo -e "${YELLOW}Memuat fungsi editor...${NC}"
    if [ -f "\$HELPER_SCRIPT" ]; then
        source "\$HELPER_SCRIPT"
        create_bot_script # Panggil fungsi dari helper
        restart_bot
    else
        echo -e "${YELLOW}File helper tidak ditemukan. Jalankan ulang instalasi utama.${NC}"
        sleep 3
    fi
}

function restart_bot() {
    echo -e "${BLUE}Me-restart service bot...${NC}"
    systemctl restart converterbot.service
    echo -e "${GREEN}Service berhasil di-restart.${NC}"
    sleep 2
}

function check_status() {
    echo -e "${BLUE}Status service bot saat ini:${NC}"
    systemctl status converterbot.service --no-pager
    echo -e "${YELLOW}\nTekan Enter untuk kembali ke menu...${NC}"
    read -r
}

function check_logs() {
    echo -e "${BLUE}Menampilkan log bot... (Tekan Ctrl+C untuk keluar)${NC}"
    journalctl -u converterbot.service -f
}

function update_script() {
    echo -e "${YELLOW}Skrip ini akan mengunduh dan menjalankan versi terbaru dari:${NC}"
    echo -e "${BLUE}\$UPDATE_URL${NC}"
    read -p "Apakah Anda yakin ingin melanjutkan? (y/n): " confirm
    if [[ \$confirm == [Yy]* ]]; then
        echo -e "${BLUE}Mengunduh dan menjalankan skrip pembaruan...${NC}"
        bash <(curl -sL \$UPDATE_URL | sed 's/\r\$//')
        echo -e "${GREEN}Proses pembaruan selesai.${NC}"
        exit 0
    else
        echo -e "${YELLOW}Pembaruan dibatalkan.${NC}"
        sleep 2
    fi
}

# Logika utama menu
while true; do
    show_menu
    read -p "Pilih opsi [1-6]: " choice
    case \$choice in
        1) edit_bot ;;
        2) restart_bot ;;
        3) check_status ;;
        4) check_logs ;;
        5) update_script ;;
        6) break ;;
        *) echo -e "${YELLOW}Pilihan tidak valid, silakan coba lagi.${NC}"; sleep 1 ;;
    esac
done
EOF
    chmod +x "$MENU_SCRIPT_PATH"
    echo -e "${GREEN}Perintah 'm-yaml' berhasil dibuat.${NC}"
}

# --- Logika Utama Skrip Instalasi ---

if [ "$(id -u)" -ne 0 ]; then
  echo -e "${YELLOW}Skrip ini perlu dijalankan dengan hak akses root atau sudo.${NC}" >&2; exit 1
fi

echo -e "${BLUE}Memulai proses instalasi/pembaruan Bot Konverter...${NC}"

# Langkah 1: Instalasi dependensi
echo -e "\n${BLUE}Langkah 1: Mengupdate sistem dan menginstal dependensi...${NC}"
apt-get update > /dev/null
apt-get install -y python3 python3-pip python3-venv curl > /dev/null
echo -e "${GREEN}Dependensi sistem siap.${NC}"

# Langkah 2: Setup direktori dan venv
echo -e "\n${BLUE}Langkah 2: Menyiapkan direktori & lingkungan virtual...${NC}"
mkdir -p "$PROJECT_DIR"
if [ ! -d "$VENV_DIR" ]; then python3 -m venv "$VENV_DIR"; fi
source "$VENV_DIR/bin/activate"
pip install -q python-telegram-bot
deactivate
echo -e "${GREEN}Direktori dan lingkungan virtual siap.${NC}"

# Langkah 3: Buat skrip bot (hanya jika belum ada)
if [ ! -f "$BOT_SCRIPT_PATH" ]; then
    echo -e "\n${BLUE}Langkah 3: Konfigurasi awal bot...${NC}"
    create_bot_script
else
    echo -e "\n${YELLOW}Langkah 3: Skrip bot sudah ada, melewati konfigurasi awal.${NC}"
fi

# Langkah 4: Buat file helper untuk menu
echo -e "\n${BLUE}Langkah 4: Membuat file helper untuk menu manajemen...${NC}"
# Salin fungsi create_bot_script ke file terpisah
declare -f create_bot_script > "$HELPER_SCRIPT_PATH"
echo -e "${GREEN}File helper berhasil dibuat.${NC}"

# Langkah 5: Buat service systemd
echo -e "\n${BLUE}Langkah 5: Membuat service systemd 'converterbot.service'...${NC}"
CURRENT_USER=${SUDO_USER:-$(whoami)}
cat << EOF > "$SERVICE_FILE"
[Unit]
Description=Telegram Converter Bot
After=network.target
[Service]
User=$CURRENT_USER
Group=nogroup
WorkingDirectory=$PROJECT_DIR
ExecStart=$VENV_DIR/bin/python $BOT_SCRIPT_PATH
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF
echo -e "${GREEN}File service systemd berhasil dibuat.${NC}"

# Langkah 6: Buat skrip menu
echo -e "\n${BLUE}Langkah 6: Membuat/Memperbarui menu manajemen...${NC}"
create_menu_script

# Langkah 7: Jalankan service
echo -e "\n${BLUE}Langkah 7: Menjalankan dan mengaktifkan service bot...${NC}"
systemctl daemon-reload
systemctl enable converterbot.service > /dev/null
systemctl restart converterbot.service

# Verifikasi
echo -e "\n${GREEN}--- PROSES SELESAI ---${NC}"
echo -e "Bot Anda sekarang berjalan 24/7."
echo -e "Gunakan perintah '${YELLOW}m-yaml${NC}' untuk mengelola bot Anda."
echo -e "Status service saat ini:"
systemctl status converterbot.service --no-pager
