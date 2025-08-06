#!/bin/bash

# ==============================================================================
# Skrip Instalasi, Manajemen, & Update Otomatis untuk Bot Telegram Konverter
# Versi 4.2 - Tanpa Otorisasi, Hasil untuk Admin & Pengguna
# ==============================================================================

# --- Konfigurasi & Variabel Global ---
PROJECT_DIR="/opt/telegram_converter_bot"
SERVICE_FILE="/etc/systemd/system/converterbot.service"
BOT_SCRIPT_PATH="$PROJECT_DIR/converter_bot.py"
VENV_DIR="$PROJECT_DIR/venv"
MENU_SCRIPT_PATH="/usr/local/bin/m-yaml"
HELPER_SCRIPT_PATH="$PROJECT_DIR/bot_helpers.sh"
GITHUB_SCRIPT_URL="https://raw.githubusercontent.com/angga2103/autoscript-vip/main/konvert-yaml.sh"

# Warna untuk output
GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'

# --- Fungsi-fungsi Pembantu ---
trap 'echo -e "${RED}Terjadi kesalahan. Proses dihentikan.${NC}"; exit 1' ERR
set -e

function create_bot_script() {
    echo -e "${YELLOW}Harap masukkan informasi bot dan notifikasi:${NC}"
    read -p "Masukkan Token Bot Telegram Anda: " BOT_TOKEN
    read -p "Masukkan ID Telegram Anda (untuk menerima notifikasi & salinan hasil): " ADMIN_ID

    if [ -z "$BOT_TOKEN" ] || [ -z "$ADMIN_ID" ]; then
        echo -e "${RED}Token Bot dan ID Notifikasi tidak boleh kosong.${NC}"; exit 1
    fi

    echo -e "${BLUE}Membuat file skrip bot di '$BOT_SCRIPT_PATH'...${NC}"
    cat << EOF > "$BOT_SCRIPT_PATH"
import logging, base64, json, html
from urllib.parse import urlparse, parse_qs, unquote
from telegram import Update, BotCommand
from telegram.ext import Application, CommandHandler, MessageHandler, filters, ContextTypes

# --- KONFIGURASI ---
BOT_TOKEN = "$BOT_TOKEN"
ADMIN_ID = $ADMIN_ID # ID untuk notifikasi dan hasil

logging.basicConfig(format='%(asctime)s - %(name)s - %(levelname)s - %(message)s', level=logging.INFO)
logger = logging.getLogger(__name__)

# --- FUNGSI PARSER (Tidak berubah) ---
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

# --- FUNGSI GENERATOR YAML (Tidak berubah) ---
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

# --- HANDLER BOT (Logika Baru yang Diperbaiki) ---
async def start_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text("👋 **Selamat Datang!**\\n\\nKirimkan link VMess, VLess, atau Trojan untuk diubah ke format YAML.", parse_mode='Markdown')

async def handle_text_message(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user = update.effective_user
    user_info = f"@{user.username}" if user.username else f"{user.first_name} (ID: {user.id})"
    
    processing_message = await update.message.reply_text("⏳ Permintaan Anda sedang diproses...")

    uris = update.message.text.strip().split('\\n'); proxies = []
    for uri in uris:
        uri = uri.strip(); proxy = None
        if not uri: continue
        try:
            if uri.startswith('vmess://'): proxy = parse_vmess(uri)
            elif uri.startswith('vless://'): proxy = parse_vless(uri)
            elif uri.startswith('trojan://'): proxy = parse_trojan(uri)
            if proxy: proxies.append(proxy)
        except Exception as e: logger.warning(f"Gagal proses URI dari {user_info}: {uri[:30]}... | Error: {e}")
    
    if not proxies:
        await processing_message.edit_text("Gagal. Tidak ada link valid yang ditemukan."); return
    
    yaml_content = generate_yaml(proxies)
    escaped_yaml = html.escape(yaml_content)

    # 1. Kirim Notifikasi & Salinan ke Admin
    try:
        notification_text = f"🔔 **Notifikasi**\\nPengguna *{html.escape(user_info)}* mengonversi *{len(proxies)}* akun."
        await context.bot.send_message(chat_id=ADMIN_ID, text=notification_text, parse_mode='HTML')
        
        admin_result_text = f"📄 Salinan Hasil dari {html.escape(user_info)}:\\n\\n<pre><code class=\\"language-yaml\\">{escaped_yaml}</code></pre>"
        await context.bot.send_message(chat_id=ADMIN_ID, text=admin_result_text, parse_mode='HTML')
    except Exception as e:
        logger.error(f"Gagal mengirim notifikasi/hasil ke admin: {e}")

    # 2. Kirim Hasil ke Pengguna Asli
    try:
        user_result_header = "✅ Berhasil! Berikut hasilnya:"
        user_message_text = f"{user_result_header}\\n\\n<pre><code class=\\"language-yaml\\">{escaped_yaml}</code></pre>"
        await processing_message.edit_text(text=user_message_text, parse_mode='HTML')
    except Exception as e:
        logger.error(f"Gagal mengirim hasil ke pengguna {user_info}: {e}")
        await processing_message.edit_text("Terjadi kesalahan saat menampilkan hasil. Admin telah menerima salinan.")

async def post_init(application: Application):
    await application.bot.set_my_commands([BotCommand("start", "Memulai bot")])

def main():
    logger.info("Mulai menjalankan bot..."); application = Application.builder().token(BOT_TOKEN).post_init(post_init).build()
    application.add_handler(CommandHandler("start", start_command))
    application.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_text_message))
    application.run_polling()
if __name__ == '__main__': main()
EOF
    echo -e "${GREEN}File skrip bot berhasil dibuat/diperbarui.${NC}"
}

# Fungsi untuk membuat skrip menu manajemen (Tidak berubah)
function create_menu_script() {
    echo -e "${BLUE}Membuat perintah manajemen 'm-yaml'...${NC}"
    cat << EOF > "$MENU_SCRIPT_PATH"
#!/bin/bash
# Skrip menu untuk mengelola bot konverter

# Warna
GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'

# Path & URL
HELPER_SCRIPT="$HELPER_SCRIPT_PATH"
UPDATE_URL="$GITHUB_SCRIPT_URL"
PROJECT_DIR_MENU="$PROJECT_DIR"
SERVICE_FILE_MENU="$SERVICE_FILE"
MENU_SCRIPT_PATH_SELF="$MENU_SCRIPT_PATH"

function show_menu() {
    clear
    echo -e "\${BLUE}=========================================\${NC}"
    echo -e "\${GREEN}  Manajemen Bot Konverter YAML${NC}"
    echo -e "\${BLUE}=========================================\${NC}"
    echo "1. Edit Bot (Ganti Token & ID Notifikasi)"
    echo "2. Restart Bot"
    echo "3. Cek Status Bot"
    echo "4. Cek Log Bot"
    echo "5. Update Skrip"
    echo -e "\${RED}6. Hapus Bot dari Server\${NC}"
    echo "7. Keluar"
    echo -e "\${BLUE}-----------------------------------------\${NC}"
}

function edit_bot() {
    echo -e "\${YELLOW}Memuat fungsi editor...${NC}"
    if [ -f "\$HELPER_SCRIPT" ]; then
        source "\$HELPER_SCRIPT"; create_bot_script; restart_bot
    else
        echo -e "\${RED}File helper tidak ditemukan. Jalankan ulang instalasi utama.${NC}"; sleep 3
    fi
}

function restart_bot() {
    echo -e "\${BLUE}Me-restart service bot...${NC}"
    systemctl restart converterbot.service
    echo -e "\${GREEN}Service berhasil di-restart.${NC}"; sleep 2
}

function check_status() {
    echo -e "\${BLUE}Status service bot saat ini:${NC}"
    systemctl status converterbot.service --no-pager
    echo -e "\${YELLOW}\nTekan Enter untuk kembali ke menu...${NC}"; read -r
}

function check_logs() {
    echo -e "\${BLUE}Menampilkan log bot... (Tekan Ctrl+C untuk keluar)${NC}"
    journalctl -u converterbot.service -f
}

function update_script() {
    echo -e "\${YELLOW}Skrip ini akan mengunduh dan menjalankan versi terbaru dari GitHub.${NC}"
    read -p "Apakah Anda yakin ingin melanjutkan? (y/n): " confirm
    if [[ \$confirm == [Yy]* ]]; then
        echo -e "\${BLUE}Mengunduh dan menjalankan skrip pembaruan...${NC}"
        bash <(curl -sL \$UPDATE_URL | sed 's/\r\$//')
        echo -e "\${GREEN}Proses pembaruan selesai. Keluar dari menu...${NC}"; exit 0
    else
        echo -e "\${YELLOW}Pembaruan dibatalkan.${NC}"; sleep 2
    fi
}

function delete_bot() {
    echo -e "\${RED}PERINGATAN! Ini akan menghapus SEMUA file bot dan service.${NC}"
    read -p "Ketik 'hapus' untuk mengonfirmasi: " confirm
    if [ "\$confirm" == "hapus" ]; then
        echo -e "\${BLUE}Memulai proses penghapusan...${NC}"
        echo "1. Menghentikan service bot..."
        systemctl stop converterbot.service || true
        echo "2. Menonaktifkan service bot..."
        systemctl disable converterbot.service || true
        echo "3. Menghapus file service..."
        rm -f "\$SERVICE_FILE_MENU"
        echo "4. Reload systemd daemon..."
        systemctl daemon-reload
        echo "5. Menghapus direktori proyek..."
        rm -rf "\$PROJECT_DIR_MENU"
        echo "6. Menghapus skrip menu ini..."
        rm -f "\$MENU_SCRIPT_PATH_SELF"
        echo -e "\${GREEN}Bot telah berhasil dihapus dari server.${NC}"
        exit 0
    else
        echo -e "\${YELLOW}Konfirmasi salah. Penghapusan dibatalkan.${NC}"; sleep 2
    fi
}

# Logika utama menu
while true; do
    show_menu
    read -p "Pilih opsi [1-7]: " choice
    case \$choice in
        1) edit_bot ;;
        2) restart_bot ;;
        3) check_status ;;
        4) check_logs ;;
        5) update_script ;;
        6) delete_bot ;;
        7) break ;;
        *) echo -e "\${RED}Pilihan tidak valid.${NC}"; sleep 1 ;;
    esac
done
EOF
    chmod +x "$MENU_SCRIPT_PATH"
    echo -e "${GREEN}Perintah 'm-yaml' berhasil dibuat.${NC}"
}

# --- Logika Utama Skrip Instalasi ---
if [ "$(id -u)" -ne 0 ]; then
  echo -e "${RED}Skrip ini perlu dijalankan dengan hak akses root atau sudo.${NC}" >&2; exit 1
fi
echo -e "${BLUE}Memulai proses instalasi/pembaruan Bot Konverter...${NC}"
echo -e "\n${BLUE}Langkah 1: Mengupdate sistem dan menginstal dependensi...${NC}"
apt-get update > /dev/null
apt-get install -y python3 python3-pip python3-venv curl > /dev/null
echo -e "\n${BLUE}Langkah 2: Menyiapkan direktori & lingkungan virtual...${NC}"
mkdir -p "$PROJECT_DIR"
if [ ! -d "$VENV_DIR" ]; then python3 -m venv "$VENV_DIR"; fi
source "$VENV_DIR/bin/activate"
pip install -q python-telegram-bot
deactivate
if [ ! -f "$BOT_SCRIPT_PATH" ]; then
    echo -e "\n${BLUE}Langkah 3: Konfigurasi awal bot...${NC}"; create_bot_script
else
    echo -e "\n${YELLOW}Langkah 3: Skrip bot sudah ada, melewati konfigurasi awal.${NC}"
fi
echo -e "\n${BLUE}Langkah 4: Membuat file helper untuk menu...${NC}"
declare -f create_bot_script > "$HELPER_SCRIPT_PATH"
echo -e "\n${BLUE}Langkah 5: Membuat service systemd...${NC}"
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
echo -e "\n${BLUE}Langkah 6: Membuat/Memperbarui menu manajemen...${NC}"
create_menu_script
echo -e "\n${BLUE}Langkah 7: Menjalankan dan mengaktifkan service bot...${NC}"
systemctl daemon-reload
systemctl enable converterbot.service > /dev/null
systemctl restart converterbot.service
echo -e "\n${GREEN}--- PROSES SELESAI ---${NC}"
echo -e "Bot Anda sekarang berjalan 24/7."
echo -e "Gunakan perintah '${YELLOW}m-yaml${NC}' untuk mengelola bot Anda."
echo -e "Status service saat ini:"
systemctl status converterbot.service --no-pager
