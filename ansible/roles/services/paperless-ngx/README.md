# Paperless-ngx

Система управления документами с автоматическим распознаванием текста (OCR). Позволяет сканировать, индексировать и искать бумажные документы в электронном виде. По умолчанию настроена на распознавание русского и английского языков.

## Переменные

| Переменная | Описание | Значение по умолчанию |
|-----------|----------|----------------------|
| `enable_paperless_ngx` | Включить/выключить сервис | `true` |
| `paperless_ngx_port` | Порт веб-интерфейса | `8012` |
| `paperless_ngx_data_dir` | Каталог для хранения данных | `/opt/paperless-ngx/data` |
| `paperless_ngx_config_dir` | Каталог конфигурации | `/opt/paperless-ngx/config` |
| `paperless_ngx_consume_dir` | Каталог для загрузки документов (входящие) | `/opt/paperless-ngx/data/consume` |
| `paperless_ngx_media_dir` | Каталог для обработанных документов | `/opt/paperless-ngx/data/media` |
| `paperless_ngx_secret_key` | Секретный ключ Django | (из passwords.yml) |
| `paperless_ngx_admin_user` | Имя пользователя суперадминистратора | `admin` |
| `paperless_ngx_admin_password` | Пароль суперадминистратора | (из passwords.yml) |
| `paperless_ngx_ocr_language` | Языки для OCR-распознавания | `rus+eng` |

## Порт

Сервис слушает на `127.0.0.1:8012`. Доступен через nginx по пути `/paperless/`.

## Данные

- **Данные**: `{{ opt_base }}/paperless-ngx/data`
  - `consume/` -- каталог для загрузки новых документов (файлы автоматически обрабатываются и удаляются)
  - `media/` -- обработанные документы, миниатюры, архивные версии
- **Конфигурация**: `{{ opt_base }}/paperless-ngx/config` -- Containerfile, `entrypoint.sh`

## Инициализация

При первом развёртывании выполняются следующие действия:

1. Создание каталогов: данные, конфигурация, входящие документы и медиа
2. Копирование Containerfile и скрипта `entrypoint.sh`
3. Сборка контейнерного образа `localhost/paperless-ngx` из Containerfile
4. Создание и запуск systemd user unit
5. Ожидание готовности Paperless-ngx
6. Создание суперпользователя Django через `manage.py` (при повторном запуске пропускается, если пользователь уже существует)
7. Настройка nginx reverse proxy

Для добавления документов скопируйте файлы (PDF, изображения) в каталог `paperless_ngx_consume_dir` -- они будут автоматически обработаны OCR и добавлены в систему.

## Зависимости

- Базовый образ: `docker.io/library/debian:13-slim`
- Роли: `base`, `podman`, `nginx`
