# OpenStreetMap

Офлайн-сервер карт на базе tileserver-gl-light. Позволяет просматривать карты OpenStreetMap без подключения к интернету, используя предварительно загруженные MBTiles-файлы с векторными тайлами.

## Переменные

| Переменная | Описание | Значение по умолчанию |
|-----------|----------|----------------------|
| `enable_openstreetmap` | Включить/выключить сервис | `true` |
| `openstreetmap_port` | Порт, на котором слушает сервис | `8002` |
| `openstreetmap_data_dir` | Каталог для хранения MBTiles-файлов | `/opt/openstreetmap/data` |
| `openstreetmap_config_dir` | Каталог конфигурации и Containerfile | `/opt/openstreetmap/config` |
| `openstreetmap_mbtiles_url` | URL для скачивания MBTiles-файла | `https://archive.org/download/osm_europe_z11-z14_2019.mbtiles/osm_europe_z11-z14_2019.mbtiles` |

## Порт

Сервис слушает на `127.0.0.1:8002`. Доступен через nginx по пути `/osm/`.

## Данные

- **Данные**: `{{ opt_base }}/openstreetmap/data` -- MBTiles-файлы карт
- **Конфигурация**: `{{ opt_base }}/openstreetmap/config` -- Containerfile для сборки образа

## Инициализация

При первом развёртывании выполняются следующие действия:

1. Создание каталогов для данных и конфигурации
2. Скачивание MBTiles-файла по URL из `openstreetmap_mbtiles_url` (файл может быть очень большим -- до десятков ГБ)
3. Сборка контейнерного образа `localhost/openstreetmap` из Containerfile
4. Создание и запуск systemd user unit
5. Настройка nginx reverse proxy

Альтернативные источники MBTiles-файлов:
- https://data.maptiler.com/downloads/ (требуется регистрация, свежие данные)
- https://archive.org/download/osm-vector-mbtiles/2020-10-planet-14.mbtiles (планета, 83 ГБ)

## Зависимости

- Базовый образ: `docker.io/library/debian:13-slim`
- Роли: `base`, `podman`, `nginx`
