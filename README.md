# Offline Box

Автономный домашний сервер на базе Debian с 17 сервисами, работающими в rootless Podman контейнерах за nginx reverse proxy. Предназначен для работы в условиях ограниченного или полностью отсутствующего интернет-соединения.

## Архитектура

Развёртывание выполняется через Ansible и проходит следующие этапы:

1. **base** -- базовая настройка системы (пакеты, пользователь `svc`, файловая структура)
2. **podman** -- установка и настройка rootless Podman для пользователя `svc`
3. **nginx** -- установка nginx с self-signed TLS сертификатом и dashboard-страницей
4. **сервисы** -- поочерёдное развёртывание включённых сервисов

Каждый сервис:
- собирается из Containerfile на базе `debian:13-slim`
- запускается как rootless Podman контейнер от пользователя `svc` (UID 1001)
- управляется через systemd user unit
- слушает только на `127.0.0.1` на своём порту
- доступен снаружи через nginx reverse proxy с self-signed TLS

## Список сервисов

| Сервис | Описание | Порт | Версия |
|--------|----------|------|--------|
| Kiwix | Офлайн-библиотека Wikipedia и других ресурсов | 8001 | apt |
| OpenStreetMap | Офлайн-карты (tileserver-gl-light) | 8002 | 5.5.0 |
| Transmission | Торрент-клиент | 8003 | apt |
| Nexus | Репозиторий пакетов (APT, PyPI, Docker) | 8004 | 3.90.2-06 |
| Nextcloud | Облачное хранилище и совместная работа | 8005 | 33.0.1 |
| Gitea | Git-репозитории и хостинг кода | 8006 | 1.25.5 |
| Jellyfin | Медиасервер для стриминга видео и аудио | 8007 | 10.11.6 |
| Calibre-web | Электронная библиотека (e-book) | 8008 | 0.6.26 |
| SearXNG | Мета-поисковая система | 8009 | 2026.3.29 |
| Vaultwarden | Менеджер паролей (Bitwarden-совместимый) | 8010 | 1.35.4 |
| Syncthing | Синхронизация файлов между устройствами | 8011 | 2.0.15 |
| Paperless-ngx | Управление документами с OCR | 8012 | 2.20.13 |
| BigBlueButton | Веб-конференции и онлайн-классы | 8013 | 2.7 |
| OpenCloud | Синхронизация и обмен файлами | 8014 | 6.0.0 |
| Mattermost | Командный мессенджер | 8015 | 11.4.3 |
| Dendrite | Matrix-сервер для децентрализованного общения | 8016 | 0.13.8 |
| MiniDLNA | DLNA/UPnP медиасервер для устройств в LAN | 8017 | apt |

## Быстрый старт

### Требования

- Управляющая машина с Ansible 2.14+
- Коллекция `containers.podman`:
  ```bash
  ansible-galaxy collection install containers.podman
  ```
- Целевой сервер с Debian 13 (Trixie) и SSH-доступом

### Развёртывание (онлайн)

1. Отредактируйте инвентарь:
   ```bash
   vim ansible/inventory/hosts.yml
   ```

2. При необходимости измените переменные:
   ```bash
   vim ansible/group_vars/all.yml
   ```

3. Сгенерируйте пароли:
   ```bash
   python3 tools/generate-passwords.py --init
   ```

4. Запустите плейбук:
   ```bash
   ansible-playbook -i ansible/inventory/hosts.yml ansible/playbook.yml
   ```

### Развёртывание (офлайн)

Для полностью офлайн-развёртывания:

1. **На машине с интернетом** скачайте все зависимости:
   ```bash
   ./tools/download-deps.sh
   ```
   Зависимости будут сохранены в каталог `deps/`.

2. Скопируйте весь репозиторий (включая `deps/`) на целевой сервер.

3. Включите офлайн-режим в `ansible/group_vars/all.yml`:
   ```yaml
   offline_mode: true
   ```

4. Запустите плейбук:
   ```bash
   ansible-playbook -i ansible/inventory/hosts.yml ansible/playbook.yml
   ```

В офлайн-режиме Containerfile'ы используют предварительно скачанные бинарники и пакеты вместо загрузки из интернета. Для apt-пакетов используется Nexus в качестве кэширующего прокси.

> **Примечание:** Для apt-пакетов, устанавливаемых внутри контейнеров, необходимо либо предварительно заполнить кэш Nexus при наличии интернета, либо настроить локальное зеркало apt. Скрипт `download-deps.sh` скачивает бинарные артефакты (Gitea, Vaultwarden, Syncthing и т.д.), pip/npm-пакеты, но не deb-пакеты из стандартных репозиториев.

Для отключения отдельных сервисов задайте `enable_<сервис>: false` в `group_vars/all.yml` или в `host_vars`.

## Конфигурация

### Глобальные переменные

Файл `ansible/group_vars/all.yml` содержит глобальные настройки:

| Переменная | Описание | Значение по умолчанию |
|-----------|----------|----------------------|
| `svc_user` | Системный пользователь для контейнеров | `svc` |
| `svc_uid` | UID сервисного пользователя | `1001` |
| `svc_home` | Домашний каталог пользователя | `/home/svc` |
| `opt_base` | Базовый каталог для данных сервисов | `/opt` |
| `listen_addr` | Адрес, на котором слушают сервисы | `127.0.0.1` |
| `server_name` | Имя сервера для nginx и TLS-сертификата | автоопределение IP |
| `use_ssl` | Включить HTTPS с self-signed сертификатом | `true` |
| `container_base_image` | Базовый образ контейнеров | `docker.io/library/debian:13-slim` |
| `offline_mode` | Офлайн-сборка из локальных зависимостей | `false` |
| `offline_deps_dir` | Каталог с предварительно скачанными зависимостями | `deps/` |

### Переменные сервисов

У каждого сервиса есть собственные переменные в `ansible/roles/services/<сервис>/defaults/main.yml`. Их можно переопределить:

- в `ansible/group_vars/all.yml` -- для всех хостов
- в `ansible/host_vars/<хост>.yml` -- для конкретного хоста
- через `-e` при запуске плейбука:
  ```bash
  ansible-playbook -i ansible/inventory/hosts.yml ansible/playbook.yml -e "enable_kiwix=false"
  ```

## Офлайн-зависимости

Скрипт `tools/download-deps.sh` скачивает следующие зависимости:

| Сервис | Что скачивается |
|--------|----------------|
| Nexus | `nexus-*-java17-unix.tar.gz` от Sonatype |
| Nextcloud | `nextcloud-*.tar.bz2` с nextcloud.com |
| Gitea | Бинарник с dl.gitea.com |
| Vaultwarden | Бинарник + web-vault с GitHub |
| Syncthing | Бинарник с GitHub |
| OpenCloud | Бинарник с GitHub |
| Mattermost | Архив с releases.mattermost.com |
| Dendrite | Бинарник с GitHub |
| BigBlueButton | `bbb-web.war` с GitHub |
| Jellyfin | GPG-ключ репозитория |
| OpenStreetMap | npm-пакет tileserver-gl-light |
| Calibre-web | pip-пакеты (calibreweb + зависимости) |
| SearXNG | pip-пакеты (searxng + зависимости) |
| Paperless-ngx | pip-пакеты (paperless-ngx, gunicorn, uvicorn + зависимости) |

Можно скачать зависимости для отдельных сервисов:
```bash
./tools/download-deps.sh nexus gitea vaultwarden
```

## Dashboard

После развёртывания по адресу `https://<server_ip>/` доступна dashboard-страница со списком всех включённых сервисов и их статусами (healthcheck). Страница автоматически генерируется из реестра сервисов `offlinebox_services`.

## Структура проекта

```
offline-box/
  ansible/
    group_vars/
      all.yml                          # Глобальные переменные
      passwords.example.yml            # Пример файла паролей
    inventory/
      hosts.yml                        # Инвентарь хостов
    playbook.yml                       # Основной плейбук
    roles/
      base/                            # Базовая настройка системы
      podman/                          # Установка Podman
      backup/                          # Настройка резервного копирования
      nginx/                           # Nginx reverse proxy + dashboard
      services/
        <сервис>/
          defaults/main.yml            # Переменные по умолчанию (версии)
          handlers/main.yml            # Хэндлеры сервиса
          tasks/main.yml               # Задачи развёртывания
          templates/
            Containerfile.j2           # Шаблон Containerfile
            <сервис>.service.j2        # Systemd user unit
            nginx-<сервис>.conf.j2     # Конфиг nginx для сервиса
  deps/                                # Офлайн-зависимости (gitignored)
  tools/
    generate-passwords.py              # Генерация паролей
    download-deps.sh                   # Скачивание зависимостей для офлайна
```

## Лицензия

Лицензия не указана.
