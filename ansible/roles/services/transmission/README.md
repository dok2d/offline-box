# Transmission

Торрент-клиент с веб-интерфейсом. Позволяет скачивать и раздавать файлы по протоколу BitTorrent. Поддерживает каталог наблюдения (watch directory) для автоматического добавления торрент-файлов.

## Переменные

| Переменная | Описание | Значение по умолчанию |
|-----------|----------|----------------------|
| `enable_transmission` | Включить/выключить сервис | `true` |
| `transmission_port` | Порт веб-интерфейса (RPC) | `8003` |
| `transmission_data_dir` | Каталог для данных | `/opt/transmission/data` |
| `transmission_config_dir` | Каталог конфигурации | `/opt/transmission/config` |
| `transmission_download_dir` | Каталог для загруженных файлов | `/opt/transmission/data/downloads` |
| `transmission_watch_dir` | Каталог наблюдения за торрент-файлами | `/opt/transmission/data/watch` |
| `transmission_rpc_username` | Имя пользователя для веб-интерфейса | `admin` |
| `transmission_rpc_password` | Пароль для веб-интерфейса | (из passwords.yml) |
| `transmission_peer_port` | Порт для входящих соединений от пиров | `51413` |
| `transmission_speed_limit_up_enabled` | Включить ограничение скорости отдачи | `false` |
| `transmission_speed_limit_up` | Ограничение скорости отдачи (КБ/с) | `1000` |
| `transmission_speed_limit_down_enabled` | Включить ограничение скорости загрузки | `false` |
| `transmission_speed_limit_down` | Ограничение скорости загрузки (КБ/с) | `5000` |

## Порт

Сервис слушает на `127.0.0.1:8003`. Доступен через nginx по пути `/transmission/`.
Порт для пиров: `51413` (TCP/UDP).

## Данные

- **Данные**: `{{ opt_base }}/transmission/data` -- основной каталог данных
  - `downloads/` -- загруженные файлы
  - `watch/` -- каталог наблюдения для автоматического добавления торрентов
- **Конфигурация**: `{{ opt_base }}/transmission/config` -- `settings.json` и Containerfile

## Инициализация

При первом развёртывании выполняются следующие действия:

1. Создание каталогов: данных, конфигурации, загрузок и наблюдения
2. Генерация `settings.json` из шаблона с заданными параметрами
3. Сборка контейнерного образа `localhost/transmission` из Containerfile
4. Создание и запуск systemd user unit
5. Настройка nginx reverse proxy

## Зависимости

- Базовый образ: `docker.io/library/debian:13-slim`
- Роли: `base`, `podman`, `nginx`
