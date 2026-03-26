# Offline Box

Автономный домашний сервер на базе Debian с 16 сервисами, работающими в rootless Podman контейнерах за nginx reverse proxy. Предназначен для работы в условиях ограниченного или полностью отсутствующего интернет-соединения.

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

| Сервис | Описание | Порт | URL |
|--------|----------|------|-----|
| Kiwix | Офлайн-библиотека Wikipedia и других ресурсов | 8001 | `/kiwix/` |
| OpenStreetMap | Офлайн-карты и навигация | 8002 | `/osm/` |
| Transmission | Торрент-клиент | 8003 | `/transmission/` |
| Nexus | Репозиторий пакетов и артефактов (APT, PyPI, Docker) | 8004 | `/nexus/` |
| Nextcloud | Облачное хранилище и совместная работа | 8005 | `/nextcloud/` |
| Gitea | Git-репозитории и хостинг кода | 8006 | `/gitea/` |
| Jellyfin | Медиасервер для стриминга видео и аудио | 8007 | `/jellyfin/` |
| Calibre-web | Электронная библиотека (e-book) | 8008 | `/calibre/` |
| SearXNG | Мета-поисковая система | 8009 | `/searxng/` |
| Vaultwarden | Менеджер паролей (совместимый с Bitwarden) | 8010 | `/vaultwarden/` |
| Syncthing | Синхронизация файлов между устройствами | 8011 | `/syncthing/` |
| Paperless-ngx | Управление документами с OCR | 8012 | `/paperless/` |
| BigBlueButton | Веб-конференции и онлайн-классы | 8013 | `/bbb/` |
| OpenCloud | Синхронизация и обмен файлами | 8014 | `/opencloud/` |
| Mattermost | Командный мессенджер | 8015 | `/mattermost/` |
| Dendrite | Matrix-сервер для децентрализованного общения | 8016 | `/dendrite/` |

## Быстрый старт

### Требования

- Управляющая машина с Ansible 2.14+
- Коллекция `containers.podman`:
  ```bash
  ansible-galaxy collection install containers.podman
  ```
- Целевой сервер с Debian 13 (Trixie) и SSH-доступом

### Развёртывание

1. Отредактируйте инвентарь:
   ```bash
   vim ansible/inventory/hosts.yml
   ```

2. При необходимости измените переменные:
   ```bash
   vim ansible/group_vars/all.yml
   ```

3. Запустите плейбук:
   ```bash
   ansible-playbook -i ansible/inventory/hosts.yml ansible/playbook.yml
   ```

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
| `container_base_image` | Базовый образ контейнеров | `docker.io/library/debian:13-slim` |

### Переменные сервисов

У каждого сервиса есть собственные переменные в `ansible/roles/services/<сервис>/defaults/main.yml`. Их можно переопределить:

- в `ansible/group_vars/all.yml` -- для всех хостов
- в `ansible/host_vars/<хост>.yml` -- для конкретного хоста
- через `-e` при запуске плейбука:
  ```bash
  ansible-playbook -i inventory playbook.yml -e "enable_kiwix=false"
  ```

## Dashboard

После развёртывания по адресу `https://<server_ip>/` доступна dashboard-страница со списком всех включённых сервисов и их статусами (healthcheck). Страница автоматически генерируется из реестра сервисов `offlinebox_services`.

## Структура проекта

```
offline-box/
  ansible/
    group_vars/
      all.yml                          # Глобальные переменные
    inventory/
      hosts.yml                        # Инвентарь хостов
    playbook.yml                       # Основной плейбук
    roles/
      base/
        tasks/main.yml                 # Базовая настройка системы
      podman/
        tasks/main.yml                 # Установка Podman
      nginx/
        handlers/main.yml              # Хэндлеры nginx
        tasks/main.yml                 # Установка и настройка nginx
        templates/
          dashboard.html.j2            # Шаблон dashboard-страницы
          nginx.conf.j2                # Основной конфиг nginx
          security-headers.conf.j2     # Заголовки безопасности
      services/
        <сервис>/
          defaults/main.yml            # Переменные по умолчанию
          files/Containerfile           # Containerfile для сборки образа
          handlers/main.yml            # Хэндлеры сервиса
          tasks/main.yml               # Задачи развёртывания
          templates/
            <сервис>.service.j2        # Systemd user unit
            nginx-<сервис>.conf.j2     # Конфиг nginx для сервиса
```

## Лицензия

Лицензия не указана.
