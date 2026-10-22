# Развёртывание WGM (срез 4 — read-only)

Документ описывает подготовку, доставку и запуск агентов и контроллера на
узлах в режиме read-only. На этом этапе не создаются и не изменяются
VPN-инстансы; старый `wg0` и работающий каскад не трогаются.

## Состав релиза

- `wgm` — OTP-приложение, собранное как Elixir release (`mix release`).
- `rel/systemd/wgm-agent.service` — юнит агента для всех узлов.
- `rel/systemd/wgm-controller.service` — юнит контроллера для входного узла.
- `rel/systemd/agent.env.example` — шаблон переменных агента.
- `rel/systemd/controller.env.example` — шаблон переменных контроллера.

## Стек на узлах

Владелец запросил установку через PPA:

```bash
add-apt-repository -y ppa:rabbitmq/rabbitmq-erlang
apt update
apt install -y git elixir erlang
```

Зафиксированные версии: Erlang/OTP 27, Elixir 1.17.3.

## Сборка

Релиз собирается на контроллере (Ubuntu 22.04, x86_64), потому что рабочая
машина разработчика — macOS, и её сборка содержит несовместимые с Linux
ERTS/NIF. Все узлы получают один и тот же tar-архив.

```bash
# на контроллере (5.129.219.31)
cd /root/wgm-build
MIX_ENV=prod mix deps.get
MIX_ENV=prod mix release
# артефакт: _build/prod/wgm-0.1.0.tar.gz
```

## Требования к узлам

- ОС: Linux с systemd.
- Установлены `wg` и `awg` (read-only агент использует их для `show all dump`).
- Открыты порты Erlang distribution: `epmd` 4369 и dist-порты 9100 (агенты) /
  9101 (контроллер) — заданы через `ERL_AFLAGS` в env-файлах.
- Общий Erlang cookie для контроллера, агентов и ноутбука — в `/etc/wgm/cookie.env`
  (root-only `0600`); systemd загружает его через `EnvironmentFile`.
- Пользователь root (агенту нужен доступ к `wg/awg show` и `ip link`).

## Доставка на узел

```bash
NODE=root@193.233.91.130
RELEASE_TAR=_build/prod/wgm-0.1.0.tar.gz

ssh $NODE 'mkdir -p /opt/wgm/releases /opt/wgm/current /etc/wgm /var/lib/wgm'
scp $RELEASE_TAR $NODE:/tmp/wgm.tar.gz
ssh $NODE 'rm -rf /opt/wgm/releases/0.1.0 && mkdir -p /opt/wgm/releases/0.1.0 && tar -xzf /tmp/wgm.tar.gz -C /opt/wgm/releases/0.1.0 && rm -f /tmp/wgm.tar.gz && ln -sfn /opt/wgm/releases/0.1.0 /opt/wgm/current'
```

## Общий cookie

Сгенерировать один cookie и разместить на всех узлах и на ноутбуке:

```bash
COOKIE=$(openssl rand -base64 32 | tr -d '\n')
printf 'RELEASE_COOKIE=%s\n' "$COOKIE" > /tmp/cookie.env
chmod 600 /tmp/cookie.env
scp /tmp/cookie.env $NODE:/etc/wgm/cookie.env
ssh $NODE 'chmod 600 /etc/wgm/cookie.env'
# для ноутбука: записать cookie в удобное место (например, ~/.wgm/cookie)
# и использовать при подключении через iex --cookie $(cat ~/.wgm/cookie)
```

## Настройка агента

На каждом узле:

```bash
scp rel/systemd/wgm-agent.service $NODE:/etc/systemd/system/
scp rel/systemd/agent.env.example $NODE:/etc/wgm/agent.env
# отредактировать /etc/wgm/agent.env под конкретный узел
```

Пример `/etc/wgm/agent.env` (entry):

```bash
WGM_NODE_ID=entry-1
WGM_NODE_NAME=entry
WGM_NODE_ADDRESS=193.233.91.130
WGM_NODE_ROLE=entry
WGM_NODE_DESCRIPTION="Cascade entry node"

RELEASE_DISTRIBUTION=name
RELEASE_NODE=wgm_agent@193.233.91.130
ERL_AFLAGS="-kernel inet_dist_listen_min 9100 inet_dist_listen_max 9100"

# Read-only наблюдение за живыми интерфейсами.
WGM_AGENT_INSTANCES="legacy-wg0:wg:wg0:51820:10.10.0.0/24:10.10.0.1/24|legacy-awg0:awg:awg0:51821:10.11.0.0/24:10.11.0.1/24"
```

Формат `WGM_AGENT_INSTANCES`: `id:protocol:name:listen_port:subnet:address|...`.
Для read-only режима ключевые поля — `protocol` и `name`; остальные могут быть
условными.

Роли:

- `entry` — входной узел каскада;
- `exit` — выходной узел каскада;
- `standalone` — отдельный узел.

## Настройка контроллера

На отдельностоящем узле (по ADR-0001 — `5.129.219.31`):

```bash
scp rel/systemd/wgm-controller.service $NODE:/etc/systemd/system/
scp rel/systemd/controller.env.example $NODE:/etc/wgm/controller.env
```

Пример `/etc/wgm/controller.env`:

```bash
RELEASE_DISTRIBUTION=name
RELEASE_NODE=wgm_controller@5.129.219.31
ERL_AFLAGS="-kernel inet_dist_listen_min 9101 inet_dist_listen_max 9101"
```

По умолчанию база данных контроллера:
`/var/lib/wgm/controller.db` (права `0600`, root-only).

## Запуск

```bash
ssh $NODE 'systemctl daemon-reload'
ssh $NODE 'systemctl enable --now wgm-agent'
# на узле с контроллером:
ssh $NODE 'systemctl enable --now wgm-controller'
```

## Проверка read-only

1. Логи:

   ```bash
   journalctl -u wgm-agent -f
   journalctl -u wgm-controller -f
   ```

2. Подключение из `iex` ноутбука к контроллеру:

   ```elixir
   iex --name wgm_client@<notebook_ip> --cookie <cookie>
   Node.connect(:wgm_controller@<controller_address>)
   GenServer.call({:wgm_controller, :wgm_controller@<controller_address>}, :status)
   ```

3. Регистрация узлов в контроллере (read-only, только наблюдение):

   ```elixir
   GenServer.call(
     :wgm_controller,
     {:register_node, "cmd-1", %{id: "entry-1", name: "entry", address: "193.233.91.130", role: :entry}}
   )
   ```

   Агенты должны ответить статусом; контроллер покажет узлы `online`.

## Ограничения среза 4

- Агенты только наблюдают; конфигурации туннелей не применяются.
- Старый `wg0` и текущий каскад не изменяются.
- Управление инстансами, пирами и каскадом — в следующих срезах.
