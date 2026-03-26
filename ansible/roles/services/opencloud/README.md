# OpenCloud

Платформа для синхронизации и обмена файлами. Предоставляет облачное хранилище с поддержкой WebDAV, мобильных клиентов и совместной работы. Написана на Go, не требует внешней базы данных.

## Переменные

| Переменная | Описание | Значение по умолчанию |
|-----------|----------|----------------------|
| `enable_opencloud` | Включить/выключить сервис | `true` |
| `opencloud_port` | Порт, на котором слушает сервис | `8014` |
| `opencloud_data_dir` | Каталог для хранения данных | `/opt/opencloud/data` |
| `opencloud_config_dir` | Каталог конфигурации | `/opt/opencloud/config` |
| `opencloud_admin_user` | Имя пользователя администратора | `admin` |
| `opencloud_admin_password` | Пароль администратора | (из passwords.yml) |
| `opencloud_secret_key` | Секретный ключ | (из passwords.yml) |
| `opencloud_upload_max_size` | Максимальный размер загружаемого файла | `10G` |

## Порт

Сервис слушает на `127.0.0.1:8014`. Доступен через nginx по пути `/opencloud/`.

## Данные

- **Данные**: `{{ opt_base }}/opencloud/data` -- пользовательские файлы
- **Конфигурация**: `{{ opt_base }}/opencloud/config` -- Containerfile, `opencloud.env`

## Инициализация

При первом развёртывании выполняются следующие действия:

1. Создание каталогов для данных и конфигурации
2. Генерация файла `opencloud.env` из шаблона
3. Сборка контейнерного образа `localhost/opencloud` из Containerfile
4. Создание и запуск systemd user unit
5. Настройка nginx reverse proxy

## Зависимости

- Базовый образ: `docker.io/library/debian:13-slim`
- Роли: `base`, `podman`, `nginx`
