# BigBlueButton

Платформа для веб-конференций и онлайн-классов. Поддерживает видео- и аудиосвязь, демонстрацию экрана, чат, интерактивную доску и запись сессий. Использует FreeSWITCH для обработки медиапотоков.

## Переменные

| Переменная | Описание | Значение по умолчанию |
|-----------|----------|----------------------|
| `enable_bigbluebutton` | Включить/выключить сервис | `true` |
| `bigbluebutton_port` | Порт веб-интерфейса | `8013` |
| `bigbluebutton_data_dir` | Каталог для хранения данных | `/opt/bigbluebutton/data` |
| `bigbluebutton_config_dir` | Каталог конфигурации | `/opt/bigbluebutton/config` |
| `bigbluebutton_recordings_dir` | Каталог для записей сессий | `/opt/bigbluebutton/data/recordings` |
| `bigbluebutton_freeswitch_port_start` | Начало диапазона UDP-портов FreeSWITCH | `16384` |
| `bigbluebutton_freeswitch_port_end` | Конец диапазона UDP-портов FreeSWITCH | `32768` |
| `bigbluebutton_version` | Версия BigBlueButton | `2.7` |
| `bigbluebutton_secret_key` | Секретный ключ API | (из passwords.yml) |
| `bigbluebutton_db_password` | Пароль базы данных | (из passwords.yml) |

## Порт

Сервис слушает на `127.0.0.1:8013`. Доступен через nginx по пути `/bbb/`.
Диапазон UDP-портов FreeSWITCH: `16384-32768`.

## Данные

- **Данные**: `{{ opt_base }}/bigbluebutton/data`
  - `recordings/` -- каталог записей конференций
- **Конфигурация**: `{{ opt_base }}/bigbluebutton/config` -- Containerfile, `bigbluebutton.properties`, `entrypoint.sh`

## Инициализация

При первом развёртывании выполняются следующие действия:

1. Создание каталогов: данные, конфигурация и записи
2. Генерация файла `bigbluebutton.env` из шаблона
3. Генерация `bigbluebutton.properties` из шаблона
4. Копирование скрипта `entrypoint.sh`
5. Сборка контейнерного образа `localhost/bigbluebutton` из Containerfile
6. Создание и запуск systemd user unit
7. Ожидание готовности BigBlueButton (healthcheck по API)
8. Настройка nginx reverse proxy

## Зависимости

- Базовый образ: `docker.io/library/debian:13-slim`
- Роли: `base`, `podman`, `nginx`
