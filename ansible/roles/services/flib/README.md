# Flib

Веб-интерфейс для поиска книг в библиотеках формата INPX. Поддерживает многотокенный поиск по автору, названию, жанру и формату, онлайн-чтение FB2, конвертацию в TXT/EPUB/PDF и скачивание файлов. Основан на Flask-приложении [flib-py](https://github.com/dok2d/flib-py).

## Переменные

| Переменная | Описание | Значение по умолчанию |
|-----------|----------|----------------------|
| `enable_flib` | Включить/выключить сервис | `true` |
| `flib_port` | Порт веб-интерфейса | `8018` |
| `flib_data_dir` | Каталог для данных (БД + архивы) | `/opt/flib/data` |
| `flib_config_dir` | Каталог конфигурации и Containerfile | `/opt/flib/config` |
| `flib_git_url` | URL Git-репозитория flib-py | `https://github.com/dok2d/flib-py.git` |
| `flib_git_ref` | Ветка/коммит для клонирования | `main` |

## Порт

Сервис слушает на `127.0.0.1:8018`. Доступен через nginx по пути `/flib/`.

Nginx использует `sub_filter` для перезаписи абсолютных путей в ответах (`/download/`, `/read/`, `/convert/` → `/flib/download/`, `/flib/read/`, `/flib/convert/`), т.к. flib-py не поддерживает sub-path нативно.

## Данные

- **Данные**: `{{ opt_base }}/flib/data`
  - `books.db` — SQLite-база книг (создаётся утилитой `inpx2sql.py` из `.inpx` файла)
  - `archives/` — ZIP-архивы с файлами книг (FB2)
- **Конфигурация**: `{{ opt_base }}/flib/config` — Containerfile, клонированный исходный код flib-py

## Подготовка данных

Данные необходимо подготовить **вручную** перед деплоем:

1. Получить INPX-файл библиотеки и соответствующие ZIP-архивы с книгами
2. Сконвертировать INPX в SQLite:
   ```bash
   python3 inpx2sql.py -i mylib_fb2.inpx -o books.db
   ```
3. Разместить файлы:
   ```
   /opt/flib/data/books.db
   /opt/flib/data/archives/*.zip
   ```

## Инициализация

При развёртывании выполняются следующие действия:

1. Создание каталогов для данных, архивов и конфигурации
2. Клонирование flib-py из Git (или копирование из offline-зависимостей)
3. Сборка контейнерного образа `localhost/flib` из Containerfile (debian:13-slim + Python venv + Flask + WeasyPrint)
4. Создание и запуск systemd user unit
5. Ожидание готовности сервиса
6. Настройка nginx reverse proxy с sub_filter

## Зависимости

- Базовый образ: `docker.io/library/debian:13-slim`
- Python-пакеты: Flask, WeasyPrint (для конвертации в PDF)
- Роли: `base`, `podman`, `nginx`
