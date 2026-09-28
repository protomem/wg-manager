#!/usr/bin/env python3
"""
WireGuard Client Manager
========================

Утилита для управления клиентами WireGuard на сервере.

Совместима по формату с исходным bash-скриптом создания клиентов:
  - peer в /etc/wireguard/wg0.conf добавляется как
        # <имя_клиента>
        [Peer]
        PublicKey = ...
        AllowedIPs = 10.10.0.X/32
    (без PresharedKey, без BEGIN/END маркеров)
  - занятые IP определяются прямым разбором wg0.conf (без отдельной БД)
  - клиентский .conf лежит в /etc/wireguard/clients/<имя>.conf,
    Address указывается как /32
  - публичный ключ сервера читается из /etc/wireguard/server1_wg0_public.key

Это значит: клиенты, созданные старым bash-скриптом, полностью видны и
управляемы этим скриптом (list/show/del), и наоборот.

Возможности:
  - создание нового клиента (генерация ключей, добавление peer'а на сервер,
    генерация готового клиентского .conf файла)
  - удаление клиента
  - вывод списка клиентов и их конфигов
  - показ конфига конкретного клиента / QR-кода для мобильных устройств

Требования:
  - Python 3.7+
  - установленный wireguard-tools (команды wg, wg-quick)
  - запуск от root (нужны права на wg0.conf и systemctl)
  - (опционально) qrencode для вывода QR-кода в терминал

Использование:
  sudo python3 wg_manager.py add <имя_клиента> [--ip 10.10.0.5]
  sudo python3 wg_manager.py del <имя_клиента>
  sudo python3 wg_manager.py list
  sudo python3 wg_manager.py show <имя_клиента> [--qr]

Конфигурация путей и параметров сервера — в блоке CONFIG ниже.
"""

import argparse
import ipaddress
import os
import shutil
import subprocess
import sys

# ============================== CONFIG ======================================

WG_INTERFACE = "wg0"                                   # имя интерфейса
WG_CONFIG_DIR = "/etc/wireguard"                       # где лежат конфиги
SERVER_CONFIG = os.path.join(WG_CONFIG_DIR, f"{WG_INTERFACE}.conf")
CLIENTS_CONFIG_DIR = os.path.join(WG_CONFIG_DIR, "clients")  # готовые .conf клиентов

# --- те же значения, что были захардкожены в bash-скрипте ---
SERVER_PUBLIC_IP = "193.233.91.130"
SERVER_PORT = "42781"
SERVER_ENDPOINT = f"{SERVER_PUBLIC_IP}:{SERVER_PORT}"
SERVER_PUBLIC_KEY_FILE = os.path.join(WG_CONFIG_DIR, "server1_wg0_public.key")

WG_NETWORK_PREFIX = "10.10.0"                 # префикс подсети (3 октета)
VPN_NETWORK = f"{WG_NETWORK_PREFIX}.0/24"     # подсеть VPN
CLIENT_DNS = "1.1.1.1"           # DNS для клиентов
CLIENT_ALLOWED_IPS = "0.0.0.0/0"  # какой трафик клиент шлёт в туннель (0.0.0.0/0 = весь трафик)
PERSISTENT_KEEPALIVE = 25

# Диапазон хостов для авто-подбора IP (как в bash: seq 2 254)
IP_RANGE_START = 2
IP_RANGE_END = 254

import re  # noqa: E402  (используется ниже для парсинга wg0.conf)

# =============================================================================


def run(cmd, input_text=None, check=True):
    """Выполнить shell-команду и вернуть stdout."""
    result = subprocess.run(
        cmd, input=input_text, capture_output=True, text=True, shell=isinstance(cmd, str)
    )
    if check and result.returncode != 0:
        print(f"[!] Команда завершилась с ошибкой: {cmd}", file=sys.stderr)
        print(result.stderr, file=sys.stderr)
        sys.exit(1)
    return result.stdout.strip()


def ensure_root():
    if os.geteuid() != 0:
        print("[!] Скрипт нужно запускать от root (sudo).", file=sys.stderr)
        sys.exit(1)


def ensure_dirs():
    os.makedirs(WG_CONFIG_DIR, exist_ok=True)
    os.makedirs(CLIENTS_CONFIG_DIR, exist_ok=True)


def parse_server_config():
    """
    Разобрать /etc/wireguard/wg0.conf и вернуть словарь клиентов вида:
        {
          name: {"ip": "10.10.0.5", "public_key": "..."},
          ...
        }

    Формат блока (как создаёт этот скрипт и старый bash-скрипт):
        # <имя>
        [Peer]
        PublicKey = ...
        PresharedKey = ...   (необязательно, для обратной совместимости)
        AllowedIPs = 10.10.0.X/32

    Это единственный источник правды — отдельная БД не используется,
    чтобы полностью совпадать по поведению с bash-версией.
    """
    if not os.path.exists(SERVER_CONFIG):
        return {}

    with open(SERVER_CONFIG) as f:
        content = f.read()

    clients = {}
    # Блок peer'а: комментарий с именем, затем [Peer] и его параметры,
    # до следующего комментария/[Peer]/конца файла.
    blocks = re.split(r"\n(?=# )", content)
    for block in blocks:
        name_match = re.match(r"# (\S+)\s*\n", block)
        if not name_match:
            continue
        name = name_match.group(1)

        if "[Peer]" not in block:
            continue

        pub_match = re.search(r"PublicKey\s*=\s*(\S+)", block)
        psk_match = re.search(r"PresharedKey\s*=\s*(\S+)", block)
        ip_match = re.search(rf"AllowedIPs\s*=\s*({re.escape(WG_NETWORK_PREFIX)}\.\d+)/32", block)

        if not pub_match or not ip_match:
            continue

        clients[name] = {
            "ip": ip_match.group(1),
            "public_key": pub_match.group(1),
            "preshared_key": psk_match.group(1) if psk_match else None,
            "config_path": os.path.join(CLIENTS_CONFIG_DIR, f"{name}.conf"),
        }

    return clients


def get_server_public_key():
    if not os.path.exists(SERVER_PUBLIC_KEY_FILE):
        print(f"[!] Не найден публичный ключ сервера: {SERVER_PUBLIC_KEY_FILE}", file=sys.stderr)
        sys.exit(1)
    with open(SERVER_PUBLIC_KEY_FILE) as f:
        return f.read().strip()


def gen_keypair():
    """Возвращает (private_key, public_key)."""
    private_key = run(["wg", "genkey"])
    public_key = run(["wg", "pubkey"], input_text=private_key)
    return private_key, public_key


def gen_psk():
    return run(["wg", "genpsk"])


def next_free_ip(clients):
    """
    Найти следующий свободный последний октет в диапазоне [2, 254],
    как это делает bash-скрипт (seq 2 254 + grep занятых AllowedIPs).
    """
    used_octets = set()
    for info in clients.values():
        ip = info["ip"]
        last_octet = ip.rsplit(".", 1)[-1]
        if last_octet.isdigit():
            used_octets.add(int(last_octet))

    for i in range(IP_RANGE_START, IP_RANGE_END + 1):
        if i not in used_octets:
            return f"{WG_NETWORK_PREFIX}.{i}"

    print(f"[!] Свободных адресов в {VPN_NETWORK} не осталось.", file=sys.stderr)
    sys.exit(1)


def apply_server_config():
    """Синхронизировать интерфейс wg0 с конфигом без разрыва соединений."""
    strip_cmd = f"wg-quick strip {WG_INTERFACE}"
    stripped = run(strip_cmd)
    proc = subprocess.run(
        ["wg", "syncconf", WG_INTERFACE, "/dev/stdin"],
        input=stripped, text=True, capture_output=True
    )
    if proc.returncode != 0:
        print("[!] Не удалось применить конфиг через wg syncconf:", proc.stderr, file=sys.stderr)
        print("[i] Попробуйте перезапустить интерфейс вручную: systemctl restart wg-quick@" + WG_INTERFACE)
        sys.exit(1)


def append_peer_to_server_config(name, public_key, ip, psk=None):
    """
    Добавить peer в конфиг сервера в том же формате, что и bash-скрипт:

        # <имя>
        [Peer]
        PublicKey = ...
        AllowedIPs = <ip>/32

    PresharedKey добавляется, только если явно передан (по умолчанию,
    как в исходном bash-скрипте, он не используется).
    """
    lines = [f"\n# {name}", "[Peer]", f"PublicKey = {public_key}"]
    if psk:
        lines.append(f"PresharedKey = {psk}")
    lines.append(f"AllowedIPs = {ip}/32")
    block = "\n".join(lines) + "\n"

    with open(SERVER_CONFIG, "a") as f:
        f.write(block)


def remove_peer_from_server_config(name):
    """
    Удалить блок peer'а вида:
        # <имя>
        [Peer]
        ...
    вплоть до начала следующего блока (следующей строки-комментария,
    начинающейся с '# ') или конца файла.
    """
    if not os.path.exists(SERVER_CONFIG):
        return
    with open(SERVER_CONFIG) as f:
        content = f.read()

    pattern = re.compile(
        rf"\n?# {re.escape(name)}\s*\n\[Peer\]\n(?:.*\n)*?(?=\n# |\Z)",
    )
    new_content = pattern.sub("", content)

    if new_content == content:
        return  # блок не найден — ничего не меняем

    with open(SERVER_CONFIG, "w") as f:
        f.write(new_content)


def build_client_config(name, client_private_key, client_ip, server_public_key, psk=None):
    """
    Собрать клиентский .conf. Формат идентичен bash-скрипту:
    Address = <ip>/32, без PresharedKey (если он не передан).
    """
    lines = [
        "[Interface]",
        f"PrivateKey = {client_private_key}",
        f"Address = {client_ip}/32",
        f"DNS = {CLIENT_DNS}",
        "",
        "[Peer]",
        f"PublicKey = {server_public_key}",
    ]
    if psk:
        lines.append(f"PresharedKey = {psk}")
    lines += [
        f"Endpoint = {SERVER_ENDPOINT}",
        f"AllowedIPs = {CLIENT_ALLOWED_IPS}",
        f"PersistentKeepalive = {PERSISTENT_KEEPALIVE}",
    ]
    return "\n".join(lines) + "\n"


# ------------------------------- Команды ------------------------------------

def cmd_add(args):
    ensure_root()
    ensure_dirs()

    if not os.path.exists(SERVER_CONFIG):
        print(f"[!] WireGuard config not found: {SERVER_CONFIG}", file=sys.stderr)
        sys.exit(1)

    clients = parse_server_config()

    name = args.name
    client_conf_path = os.path.join(CLIENTS_CONFIG_DIR, f"{name}.conf")

    if name in clients or os.path.exists(client_conf_path):
        print(f"[!] Client already exists: {name}", file=sys.stderr)
        sys.exit(1)

    if args.ip:
        ip = args.ip
        try:
            ipaddress.ip_address(ip)
        except ValueError:
            print(f"[!] Некорректный IP: {ip}", file=sys.stderr)
            sys.exit(1)
    else:
        ip = next_free_ip(clients)

    client_private_key, client_public_key = gen_keypair()
    server_public_key = get_server_public_key()

    # PresharedKey не используется — для полной совместимости с bash-скриптом.
    # Если нужен psk, раскомментируйте строку ниже и передайте psk дальше.
    # psk = gen_psk()
    psk = None

    # 1. добавляем peer в конфиг сервера (тот же формат, что у bash-скрипта)
    append_peer_to_server_config(name, client_public_key, ip, psk)

    # 2. применяем без разрыва текущих туннелей
    apply_server_config()

    # 3. генерируем клиентский конфиг
    client_conf = build_client_config(name, client_private_key, ip, server_public_key, psk)
    os.makedirs(CLIENTS_CONFIG_DIR, exist_ok=True)
    os.chmod(CLIENTS_CONFIG_DIR, 0o700)
    with open(client_conf_path, "w") as f:
        f.write(client_conf)
    os.chmod(client_conf_path, 0o600)

    print()
    print(f"Client created: {name}")
    print(f"Client IP: {ip}")
    print(f"Config: {client_conf_path}")
    print()

    if shutil.which("qrencode"):
        print("QR code:")
        subprocess.run(["qrencode", "-t", "ansiutf8"], input=client_conf, text=True)
        print()
    else:
        print("[i] qrencode не установлен, QR-код не показан (apt install qrencode).")


def cmd_del(args):
    ensure_root()
    clients = parse_server_config()
    name = args.name

    client_conf_path = os.path.join(CLIENTS_CONFIG_DIR, f"{name}.conf")

    if name not in clients and not os.path.exists(client_conf_path):
        print(f"[!] Клиент '{name}' не найден.", file=sys.stderr)
        sys.exit(1)

    remove_peer_from_server_config(name)
    apply_server_config()

    if os.path.exists(client_conf_path):
        os.remove(client_conf_path)

    print(f"[+] Клиент '{name}' удалён.")


def cmd_list(args):
    clients = parse_server_config()
    if not clients:
        print("Клиентов нет.")
        return

    print(f"{'Имя':<20}{'IP':<16}{'Публичный ключ'}")
    print("-" * 90)
    for name, info in sorted(clients.items()):
        print(f"{name:<20}{info['ip']:<16}{info['public_key']}")


def cmd_show(args):
    clients = parse_server_config()
    name = args.name

    client_conf_path = os.path.join(CLIENTS_CONFIG_DIR, f"{name}.conf")

    if name not in clients and not os.path.exists(client_conf_path):
        print(f"[!] Клиент '{name}' не найден.", file=sys.stderr)
        sys.exit(1)

    if not os.path.exists(client_conf_path):
        print(f"[!] Файл конфига не найден: {client_conf_path}", file=sys.stderr)
        sys.exit(1)

    with open(client_conf_path) as f:
        content = f.read()

    print(content)

    if args.qr:
        try:
            subprocess.run(["qrencode", "-t", "ansiutf8"], input=content, text=True, check=True)
        except FileNotFoundError:
            print("[!] Утилита 'qrencode' не установлена (apt install qrencode).", file=sys.stderr)
        except subprocess.CalledProcessError:
            print("[!] Не удалось построить QR-код.", file=sys.stderr)


# --------------------------------- CLI ---------------------------------------

def main():
    parser = argparse.ArgumentParser(description="Управление клиентами WireGuard")
    subparsers = parser.add_subparsers(dest="command", required=True)

    p_add = subparsers.add_parser("add", help="создать нового клиента")
    p_add.add_argument("name", help="имя клиента")
    p_add.add_argument("--ip", help="конкретный IP клиента (по умолчанию — автоматически)")
    p_add.set_defaults(func=cmd_add)

    p_del = subparsers.add_parser("del", help="удалить клиента")
    p_del.add_argument("name", help="имя клиента")
    p_del.set_defaults(func=cmd_del)

    p_list = subparsers.add_parser("list", help="список клиентов")
    p_list.set_defaults(func=cmd_list)

    p_show = subparsers.add_parser("show", help="показать конфиг клиента")
    p_show.add_argument("name", help="имя клиента")
    p_show.add_argument("--qr", action="store_true", help="показать QR-код конфига")
    p_show.set_defaults(func=cmd_show)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
