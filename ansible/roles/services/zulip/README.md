# Zulip

Командный чат с открытым исходным кодом. Поддерживает потоки (threads) как первоклассный элемент интерфейса, что отличает его от Slack/Mattermost. Включает: каналы, теги, поиск, интеграции, мобильные приложения, API. Официальный образ Docker содержит все компоненты в одном контейнере (Django + PostgreSQL + RabbitMQ + Redis + Memcached через supervisord).

Отключён по умолчанию (`enable_zulip: false`). Требует значительных ресурсов (минимум 2 ГБ RAM).

## Переменные

| Переменная | Описание | Значение по умолчанию |
|-----------|----------|----------------------|
| `enable_zulip` | Включить/выключить сервис | `false` |
| `zulip_port` | Порт веб-интерфейса | `8020` |
| `zulip_data_dir` | Каталог для данных | `/opt/zulip/data` |
| `zulip_config_dir` | Каталог конфигурации | `/opt/zulip/config` |
| `zulip_admin_email` | Email администратора | `admin@localhost` |
| `zulip_version` | Версия образа docker-zulip | `9.3-0` |
| `zulip_secret_key` | Секретный ключ приложения | `passwords.yml` |

## Порт

Сервис слушает на `127.0.0.1:8020` (внутренний порт контейнера: 80, HTTPS отключён).

Nginx проксирует несколько путей, так как Zulip генерирует абсолютные URL:
- `/zulip/` → интерфейс (с strip prefix)
- `/static/` → статические ресурсы
- `/api/` → REST API и WebSocket
- `/json/` → JSON API
- `/accounts/` → аутентификация
- `/user_uploads/` → загруженные файлы

> **Ограничение**: Zulip не поддерживает sub-path нативно. `SETTING_EXTERNAL_HOST` должен быть установлен на `server_name` (hostname без пути). Все пути Zulip доступны от корня через отдельные nginx location-блоки.

## Данные

- **Данные**: `{{ opt_base }}/zulip/data` — всё хранится в `/data` внутри контейнера:
  - PostgreSQL база данных
  - Загруженные файлы пользователей
  - Настройки и секреты Zulip
- **Конфигурация**: `{{ opt_base }}/zulip/config` — Containerfile, zulip.env

## Инициализация

При первом развёртывании:

1. Создание каталогов для данных и конфигурации
2. Развёртывание env-файла с секретами (`zulip.env`, права 0640)
3. Сборка образа на основе `docker.io/zulip/docker-zulip:{{ zulip_version }}`
4. Создание и запуск systemd user unit
5. Ожидание готовности (~2-3 минуты при первом запуске: инициализация PostgreSQL, миграции Django)
6. Настройка nginx

При первом запуске Zulip автоматически создаёт базу данных и отправляет приглашение администратору на `zulip_admin_email`. Если email не настроен, создайте аккаунт вручную:

```bash
podman exec -it zulip /home/zulip/deployments/current/manage.py create_realm \
  --name "My Organization" --emails admin@localhost --string-id my-org
```

## Секреты

Определяются в `ansible/group_vars/passwords.yml` (генерируется через `tools/generate-passwords.py`):

| Переменная | Описание |
|-----------|----------|
| `zulip_secret_key` | Django SECRET_KEY (длинная случайная строка) |

## Зависимости

- Базовый образ: `docker.io/zulip/docker-zulip:{{ zulip_version }}` (исключение из стандартного `container_base_image`)
- Встроено: PostgreSQL 14, RabbitMQ, Redis, Memcached
- Роли: `base`, `podman`, `nginx`
