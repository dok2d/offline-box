# Dendrite

Лёгкий Matrix-сервер (homeserver), написанный на Go. Реализует протокол Matrix для децентрализованного обмена сообщениями, поддерживает федерацию, end-to-end шифрование и обмен медиафайлами. Использует встроенную SQLite базу данных.

## Переменные

| Переменная | Описание | Значение по умолчанию |
|-----------|----------|----------------------|
| `enable_dendrite` | Включить/выключить сервис | `true` |
| `dendrite_port` | Порт HTTP API | `8016` |
| `dendrite_data_dir` | Каталог для хранения данных | `/opt/dendrite/data` |
| `dendrite_config_dir` | Каталог конфигурации | `/opt/dendrite/config` |
| `dendrite_server_name` | Имя Matrix-сервера | `{{ server_name }}` |
| `dendrite_admin_password` | Пароль администратора | (из passwords.yml) |
| `dendrite_private_key` | Приватный ключ подписи | (из passwords.yml) |
| `dendrite_registration_disabled` | Отключить регистрацию | `true` |

## Порт

Сервис слушает на `127.0.0.1:8016`. Доступен через nginx по пути `/dendrite/` и `/_matrix/`.

## Данные

- **Данные**: `{{ opt_base }}/dendrite/data` -- база данных SQLite, медиафайлы, JetStream
- **Конфигурация**: `{{ opt_base }}/dendrite/config` -- `dendrite.yaml`, `matrix_key.pem`, Containerfile

## Инициализация

При первом развёртывании выполняются следующие действия:

1. Создание каталогов для данных и конфигурации
2. Генерация конфигурации `dendrite.yaml` из шаблона
3. Генерация ключа подписи `matrix_key.pem`
4. Сборка контейнерного образа `localhost/dendrite` из Containerfile
5. Создание и запуск systemd user unit
6. Ожидание готовности Dendrite
7. Создание пользователя-администратора
8. Настройка nginx reverse proxy

## Клиенты Matrix

Для подключения к серверу можно использовать:
- Element (веб, десктоп, мобильные)
- FluffyChat
- Nheko
- Любой клиент с поддержкой протокола Matrix

## Зависимости

- Базовый образ: `docker.io/library/debian:13-slim`
- Роли: `base`, `podman`, `nginx`
