# CLAUDE.md — Offline Box Project Conventions

## Общие правила для Claude Code

- Использовать только чат, никаких форм опроса (AskUserQuestion)
- Язык общения: русский, код и конфиги на английском
- Не создавать PR без явной просьбы

## Архитектура

Автономный домашний сервер: Ansible → rootless Podman → nginx reverse proxy.
Структура по образцу kolla-ansible: per-service inventory groups, per-service plays.

### Слои

1. **base** — пакеты, пользователь `svc`, UFW, logrotate
2. **podman** — rootless podman, subuid/subgid, lingering, containers env dir
3. **nginx** — self-signed TLS, dashboard, per-service location blocks
4. **services/** — по одной роли на каждый сервис
5. **backup** — ежедневный бэкап данных сервисов

### Глобальные переменные

Определены в `ansible/group_vars/all.yml`:

| Переменная | Описание |
|---|---|
| `svc_user` / `svc_uid` / `svc_home` | Пользователь для контейнеров (`svc`, 1001, `/home/svc`) |
| `opt_base` | Базовый каталог данных (`/opt`) |
| `listen_addr` | Адрес прослушивания (`127.0.0.1`) |
| `server_name` | IP/hostname для nginx и TLS |
| `container_base_image` | Базовый образ (`docker.io/library/debian:13-slim`) |
| `container_log_dir` | Логи контейнеров (`/var/log/containers`) |
| `offline_mode` / `offline_deps_dir` | Офлайн-режим |

## Инвенторка (kolla-ansible стиль)

Два файла: `inventory/all-in-one` (всё на одном хосте) и `inventory/multinode` (распределение).

### Структура

```ini
# Tier 1 — физические группы (редактирует оператор)
[control]
localhost ansible_connection=local

# Tier 2 — сервисные группы (наследуют через :children)
[kiwix:children]
control
```

### Правила

- Каждый сервис ДОЛЖЕН иметь свою группу в обоих inventory-файлах
- В `all-in-one` все группы наследуют от `[control]`
- В `multinode` группы наследуют от tier-1 групп (`media`, `infra`, `comms`, `download`, `search`)
- Имя группы = имя сервиса = имя роли = `hosts:` в playbook

## Playbook

Файл: `ansible/playbook.yml`

### Структура play для сервиса

```yaml
- name: Apply role <service-name>
  hosts: <service-name>
  become: true
  gather_facts: false
  roles:
    - role: services/<service-name>
      when: enable_<service_var> | bool
```

### Правила

- `name:` всегда `Apply role <service-name>`
- `hosts:` = имя inventory-группы сервиса
- `gather_facts: false` — факты собираются один раз в первом play
- `when:` использует `enable_<service_var> | bool` (underscores, не hyphens)
- Новые сервисы добавляются ПЕРЕД секцией `# Backup`

## Реестр сервисов (`offlinebox_services`)

В `ansible/group_vars/all.yml`. Каждая запись:

```yaml
<service-name>:
  container_name: <service-name>
  enabled: "{{ enable_<service_var> }}"
  image: "{{ <service_var>_image_full }}"
  port: "{{ <service_var>_port }}"
  data_dir: "{{ <service_var>_data_dir }}"
  config_dir: "{{ <service_var>_config_dir }}"
  dashboard:
    name: <Human Name>
    desc: "<Short description>"
    icon: "<Unicode emoji>"
    url: /<url-prefix>/
```

### Правила

- `container_name` = имя сервиса (как в inventory)
- `enabled` ссылается на `enable_<service_var>` из role defaults
- Для сервисов с дефисом: `calibre-web` → `enable_calibre_web`, `calibre_web_port`
- `dashboard.url` ДОЛЖЕН заканчиваться на `/`
- `dashboard.icon` — Unicode emoji (одна штука)

## Роль сервиса

Каталог: `ansible/roles/services/<service-name>/`

### Обязательные файлы

```
defaults/main.yml
tasks/main.yml
handlers/main.yml
README.md
templates/
  Containerfile.j2
  <service-name>.service.j2
  nginx-<service-name>.conf.j2
```

### defaults/main.yml

```yaml
---
enable_<service_var>: true   # или false для тяжёлых сервисов

<service_var>_port: <NNNN>
<service_var>_data_dir: "{{ opt_base }}/<service-name>/data"
<service_var>_config_dir: "{{ opt_base }}/<service-name>/config"

# Версия (если есть)
<service_var>_version: "<X.Y.Z>"

# Образ
<service_var>_tag: "{{ <service_var>_version }}"   # или "latest"
<service_var>_image: "{{ (container_registry ~ '/' if container_registry else '') }}{{ (container_namespace ~ '/' if container_namespace else '') }}<service-name>"
<service_var>_image_full: "{{ <service_var>_image }}:{{ <service_var>_tag }}"
```

#### Правила именования переменных

- `enable_<service_var>` — дефисы заменяются на underscores
- Порты: 8001-8018 последовательно (следующий: 8019)
- `data_dir` — персистентные данные (БД, файлы пользователей)
- `config_dir` — контекст сборки (Containerfile, конфиги приложения)
- `_version` → `_tag` → `_image` → `_image_full` — цепочка для образа
- Пароли НЕ определяются в defaults — только в `passwords.example.yml`

### tasks/main.yml — каноничный порядок задач

```
1.  Create data directory
2.  Create config directory
3.  [Create subdirectories (archives, media, etc.)]
4.  [Deploy app config files (notify: Restart)]
5.  Deploy Containerfile.j2 → config_dir/Containerfile (register: _containerfile)
6.  [Clone source / Copy offline deps]
7.  Build container image (notify: Restart <service>)
8.  Deploy systemd user unit
9.  Enable and start service (state: started, daemon_reload: true)
10. [Wait for service health check]
11. [Post-deploy config (admin user, initial setup)]
12. Deploy nginx config (notify: Reload nginx)
```

#### Правила

- Директории ВСЕГДА создаются ДО файлов в них
- `_containerfile` — регистр для отслеживания изменений Containerfile
- `force: "{{ _containerfile.changed | default(true) }}"` — пересборка образа при изменении
- `notify: Restart <service-name>` — ОБЯЗАТЕЛЬНО на задаче build image
- `notify: Reload nginx` — ОБЯЗАТЕЛЬНО на задаче deploy nginx config
- `become_user: "{{ svc_user }}"` — для задач podman build, systemd enable, exec
- Конфиги с секретами: `diff: false`, `mode: "0600"`
- Конфиги без секретов: `diff: true`, `mode: "0644"`
- Offline mode: `when: offline_mode | default(false)` для copy задач
- Health check: `retries: 30, delay: 5, until: ... is not failed`

### handlers/main.yml

```yaml
---
- name: Restart <service-name>
  become: true
  become_user: "{{ svc_user }}"
  ansible.builtin.systemd:
    name: <service-name>
    scope: user
    state: restarted
    daemon_reload: true
```

- Имя handler = `Restart <service-name>` (с заглавной R)

### Containerfile.j2

```dockerfile
FROM {{ container_base_image }}
RUN apt-get update && \
    apt-get install -y --no-install-recommends <packages> && \
    rm -rf /var/lib/apt/lists/*

# Offline mode branching
{% if offline_mode | default(false) %}
COPY <local-deps> /tmp/
RUN <install from local>
{% else %}
RUN <download and install>
{% endif %}

RUN useradd -r -u 10001 -m <appuser> && \
    mkdir -p <dirs> && \
    chown -R <appuser>:<appuser> <dirs>
USER <appuser>
EXPOSE {{ <service_var>_port }}
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD curl -fs http://localhost:{{ <service_var>_port }}/<path> || exit 1
ENTRYPOINT [<command>]
```

#### Правила

- Базовый образ: `{{ container_base_image }}` (НЕ хардкодить `python:3.9-slim` и т.д.)
  - Исключение: BigBlueButton использует `ubuntu:22.04` (Ubuntu-специфичные пакеты)
- `apt-get update && install && rm -rf /var/lib/apt/lists/*` — в одном RUN
- Пользователь: UID `10001` (соглашение проекта)
- `EXPOSE` — использовать `{{ <service_var>_port }}`
- `HEALTHCHECK` — ОБЯЗАТЕЛЬНО, с шаблонным портом (НЕ хардкодить)
- `ENTRYPOINT` — использовать `{{ <service_var>_port }}` для порта
- Секреты (пароли, ключи) — передавать через env-файл, НЕ через Containerfile

### systemd service.j2

```ini
[Unit]
Description=<Human name> (podman)
After=default.target

[Service]
Environment="XDG_RUNTIME_DIR=/run/user/{{ svc_uid }}"
ExecStartPre=-/usr/bin/podman rm -f <service-name>
ExecStart=/usr/bin/podman run \
  --name <service-name> \
  --replace \
  --rm \
  --cap-drop=ALL \
  --security-opt=no-new-privileges \
  -p {{ listen_addr }}:{{ <service_var>_port }}:{{ <service_var>_port }} \
  --log-driver=k8s-file \
  --log-opt=path={{ container_log_dir }}/<service-name>/<service-name>.log \
  -v {{ <service_var>_data_dir }}:/data:ro \
  -v {{ <service_var>_config_dir }}:/config:rw \
  {{ <service_var>_image_full }}
ExecStop=/usr/bin/podman stop <service-name>
MemoryMax=512M
CPUQuota=100%
Restart=on-failure
RestartSec=10s

[Install]
WantedBy=default.target
```

#### Правила

- `--cap-drop=ALL` и `--security-opt=no-new-privileges` — ОБЯЗАТЕЛЬНО
- Порт: `{{ listen_addr }}:{{ port }}:{{ port }}` — НЕ хардкодить внутренний порт
- `--log-driver=k8s-file` с путём в `{{ container_log_dir }}`
- `MemoryMax` и `CPUQuota` — ОБЯЗАТЕЛЬНО, подбирать по нагрузке:

| MemoryMax | Сервисы |
|-----------|---------|
| 512M | kiwix, vaultwarden, calibre-web, flib, minidlna, searxng |
| 1G | nextcloud, gitea, dendrite, opencloud, openstreetmap, syncthing, transmission |
| 2G | nexus, paperless-ngx |
| 4G | jellyfin, bigbluebutton |

| CPUQuota | Сервисы |
|----------|---------|
| 100% | kiwix, vaultwarden, calibre-web, flib, searxng |
| 200% | nextcloud, gitea, dendrite, nexus, opencloud, openstreetmap, syncthing, transmission, minidlna |
| 400% | jellyfin, paperless-ngx |
| 800% | bigbluebutton |

- `Restart=on-failure`, `RestartSec=10s`
- Для env-файлов: `--env-file {{ svc_home }}/.config/containers/<service>.env`
- Данные: обычно `:ro` если сервис не пишет, `:rw` если пишет

### nginx config.j2

```nginx
# <Human name>
location /<url-prefix>/ {
    proxy_pass http://{{ listen_addr }}:{{ <service_var>_port }}/<backend-path>/;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    include /etc/nginx/snippets/security-headers.conf;
    limit_req zone=general burst=20 nodelay;
}
```

#### Правила

- `proxy_pass` — если бэкенд поддерживает prefix, передавать с prefix; если нет — strip через trailing `/`
- WebSocket (если нужен):
  ```nginx
  proxy_http_version 1.1;
  proxy_set_header Upgrade $http_upgrade;
  proxy_set_header Connection "upgrade";
  ```
- `client_max_body_size` — для сервисов с upload (Nextcloud, Gitea, Nexus, Vaultwarden и т.д.)
- `proxy_read_timeout` — для долгих операций (streaming, git push, OCR, WebSocket)
- `proxy_buffering off` — для streaming (Jellyfin)
- `proxy_request_buffering off` — для больших upload (Nextcloud, OpenCloud)
- Rate limit zone: `general` (30r/s) для большинства; `api` (10r/s) для лёгких API
- `sub_filter` — если бэкенд не поддерживает sub-path нативно (flib, syncthing)
  - При использовании `sub_filter`: добавить `proxy_set_header Accept-Encoding "";`

## Пароли и секреты

- `ansible/group_vars/passwords.example.yml` — шаблон (пустые значения)
- `ansible/group_vars/passwords.yml` — gitignored, заполняется через `tools/generate-passwords.py`
- НЕ определять пароли в role defaults (они перезатрут passwords.yml по приоритету)
- НЕ встраивать пароли в Containerfile (видны через `podman history`)
- Передавать через env-файлы с `mode: "0600"` и `diff: false`

## Offline-режим

### Containerfile: условная сборка

```dockerfile
{% if offline_mode | default(false) %}
COPY <local-file> /tmp/
RUN <install from local>
{% else %}
RUN <download and install>
{% endif %}
```

### tasks: копирование зависимостей

```yaml
- name: Copy offline deps for <Service>
  ansible.builtin.copy:
    src: "{{ offline_deps_dir }}/<service-name>/"
    dest: "{{ <service_var>_config_dir }}/"
    ...
  when: offline_mode | default(false)
```

- Задача копирования ПЕРЕД задачей build image
- Путь: `{{ offline_deps_dir }}/<service-name>/`

### download-deps.sh

Для каждого сервиса:
1. Извлечь версию в начале скрипта: `*_VERSION=$(get_var ...)`
2. Создать функцию `dl_<service_name>()` (underscores вместо дефисов)
3. Добавить имя в массив `ALL_SERVICES`

Типы скачивания:
- `download` — для бинарников/архивов
- `clone_repo` — для git-репозиториев
- `download_pip_with_deps` — для pip-пакетов
- `download_npm_tarball` — для npm-пакетов
- `save_image` — для Docker-образов (multi-stage builds)

## Известные исключения из паттернов

| Сервис | Исключение | Причина |
|--------|-----------|---------|
| bigbluebutton | `FROM ubuntu:22.04` вместо `container_base_image` | Ubuntu-специфичные пакеты (FreeSWITCH, PostgreSQL) |
| bigbluebutton | `--cap-add=NET_RAW`, `--cap-add=SYS_NICE` | FreeSWITCH требует raw sockets |
| minidlna | `--network=host` вместо `-p` | SSDP/UPnP multicast discovery |
| vaultwarden, dendrite | Multi-stage `FROM docker.io/...` | Бинарники копируются из upstream-образов |
| flib | `sub_filter` в nginx | flib-py не поддерживает sub-path нативно |
| syncthing | GUI не работает через sub-path | Архитектурное ограничение Syncthing |

### Порты (текущее распределение)

| Порт | Сервис |
|------|--------|
| 8001 | kiwix |
| 8002 | openstreetmap |
| 8003 | transmission |
| 8004 | nexus |
| 8005 | nextcloud |
| 8006 | gitea |
| 8007 | jellyfin |
| 8008 | calibre-web |
| 8009 | searxng |
| 8010 | vaultwarden |
| 8011 | syncthing |
| 8012 | paperless-ngx |
| 8013 | bigbluebutton |
| 8014 | opencloud |
| 8015 | mattermost |
| 8016 | dendrite |
| 8017 | minidlna |
| 8018 | flib |

Следующий свободный порт: **8019**

## Добавление нового сервиса — чеклист

1. [ ] Создать `ansible/roles/services/<name>/defaults/main.yml`
2. [ ] Создать `ansible/roles/services/<name>/tasks/main.yml`
3. [ ] Создать `ansible/roles/services/<name>/handlers/main.yml`
4. [ ] Создать `ansible/roles/services/<name>/README.md`
5. [ ] Создать `ansible/roles/services/<name>/templates/Containerfile.j2`
6. [ ] Создать `ansible/roles/services/<name>/templates/<name>.service.j2`
7. [ ] Создать `ansible/roles/services/<name>/templates/nginx-<name>.conf.j2`
8. [ ] Добавить запись в `offlinebox_services` (group_vars/all.yml)
9. [ ] Добавить play в `playbook.yml` (перед секцией Backup)
10. [ ] Добавить группу `[<name>:children]` в `inventory/all-in-one`
11. [ ] Добавить группу `[<name>:children]` в `inventory/multinode`
12. [ ] Добавить функцию `dl_<name>()` в `tools/download-deps.sh`
13. [ ] Добавить пароли в `passwords.example.yml` (если нужны)
14. [ ] Обновить README.md (таблица сервисов, счётчик)

## Валидация

После любых изменений:

```bash
# Проверка YAML
python3 -c "import yaml; yaml.safe_load(open('ansible/playbook.yml'))"

# Проверка что все HEALTHCHECK порты шаблонизированы
grep -rn 'HEALTHCHECK.*localhost:[0-9]' ansible/roles/services/*/templates/Containerfile.j2

# Проверка что все systemd порты шаблонизированы
grep -rn -- '-p.*:[0-9]\{4\} \\' ansible/roles/services/*/templates/*.service.j2

# Проверка что все сервисы имеют notify на build
for f in ansible/roles/services/*/tasks/main.yml; do
  svc=$(echo $f | sed 's|.*/services/||;s|/tasks.*||')
  grep -q "notify: Restart" "$f" && echo "OK: $svc" || echo "MISSING: $svc"
done
```
