# Vaultwarden

Легковесная реализация сервера Bitwarden, написанная на Rust. Менеджер паролей с веб-интерфейсом, совместимый со всеми клиентами Bitwarden (браузерные расширения, мобильные приложения, десктопные клиенты).

## Переменные

| Переменная | Описание | Значение по умолчанию |
|-----------|----------|----------------------|
| `enable_vaultwarden` | Включить/выключить сервис | `true` |
| `vaultwarden_port` | Порт веб-интерфейса | `8010` |
| `vaultwarden_data_dir` | Каталог для хранения данных | `/opt/vaultwarden/data` |
| `vaultwarden_config_dir` | Каталог конфигурации | `/opt/vaultwarden/config` |
| `vaultwarden_admin_token` | Токен для доступа к панели администратора (`/admin`) | `changeme-generate-long-random-string` |
| `vaultwarden_signups_allowed` | Разрешить самостоятельную регистрацию пользователей | `true` |

## Порт

Сервис слушает на `127.0.0.1:8010`. Доступен через nginx по пути `/vaultwarden/`.

## Данные

- **Данные**: `{{ opt_base }}/vaultwarden/data` -- база данных SQLite с хранилищами паролей, вложения
- **Конфигурация**: `{{ opt_base }}/vaultwarden/config` -- Containerfile

## Инициализация

При первом развёртывании выполняются следующие действия:

1. Создание каталогов для данных и конфигурации
2. Сборка контейнерного образа `localhost/vaultwarden` из Containerfile
3. Создание и запуск systemd user unit
4. Настройка nginx reverse proxy

После развёртывания зарегистрируйте первого пользователя через веб-интерфейс. Панель администратора доступна по пути `/vaultwarden/admin` с использованием `vaultwarden_admin_token`.

## Зависимости

- Базовый образ: `docker.io/library/debian:13-slim`
- Роли: `base`, `podman`, `nginx`
