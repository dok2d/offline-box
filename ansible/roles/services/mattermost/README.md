# Mattermost

Платформа для командного общения и обмена сообщениями. Предоставляет каналы, личные сообщения, обмен файлами, поиск и интеграции. Использует SQLite в качестве базы данных по умолчанию.

## Переменные

| Переменная | Описание | Значение по умолчанию |
|-----------|----------|----------------------|
| `enable_mattermost` | Включить/выключить сервис | `true` |
| `mattermost_port` | Порт веб-интерфейса | `8015` |
| `mattermost_data_dir` | Каталог для хранения данных | `/opt/mattermost/data` |
| `mattermost_config_dir` | Каталог конфигурации | `/opt/mattermost/config` |
| `mattermost_admin_user` | Имя пользователя администратора | `admin` |
| `mattermost_admin_email` | Email администратора | `admin@localhost` |

## Порт

Сервис слушает на `127.0.0.1:8015`. Доступен через nginx по пути `/mattermost/`.

## Данные

- **Данные**: `{{ opt_base }}/mattermost/data` -- база данных SQLite, загруженные файлы
- **Конфигурация**: `{{ opt_base }}/mattermost/config` -- Containerfile, `mattermost.env`

## Инициализация

При первом развёртывании выполняются следующие действия:

1. Создание каталогов для данных и конфигурации
2. Генерация файла `mattermost.env` из шаблона
3. Сборка контейнерного образа `localhost/mattermost` из Containerfile
4. Создание и запуск systemd user unit
5. Ожидание готовности Mattermost
6. Настройка nginx reverse proxy

## Зависимости

- Базовый образ: `docker.io/library/debian:13-slim`
- Роли: `base`, `podman`, `nginx`
