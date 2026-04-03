# Kiwix

Офлайн-библиотека для чтения контента Wikipedia и других ресурсов без интернета. Использует формат ZIM-файлов и сервер kiwix-serve для предоставления веб-интерфейса.

## Переменные

| Переменная | Описание | Значение по умолчанию |
|-----------|----------|----------------------|
| `enable_kiwix` | Включить/выключить сервис | `true` |
| `kiwix_port` | Порт, на котором слушает сервис | `8001` |
| `kiwix_data_dir` | Каталог для хранения ZIM-файлов и library.xml | `/opt/kiwix/data` |
| `kiwix_config_dir` | Каталог конфигурации и Containerfile | `/opt/kiwix/config` |
| `kiwix_zim_urls` | Список URL-адресов ZIM-файлов для скачивания | `["https://download.kiwix.org/zim/wikipedia/wikipedia_ru_all_maxi_2026-02.zim"]` |

## Порт

Сервис слушает на `127.0.0.1:8001`. Доступен через nginx по пути `/kiwix/`.

## Данные

- **Данные**: `{{ opt_base }}/kiwix/data` -- ZIM-файлы и файл `library.xml`
- **Конфигурация**: `{{ opt_base }}/kiwix/config` -- Containerfile для сборки образа

## Инициализация

При первом развёртывании выполняются следующие действия:

1. Создание каталогов для данных и конфигурации
2. Скачивание ZIM-файлов по URL-адресам из `kiwix_zim_urls` (может занять длительное время в зависимости от размера файлов)
3. Сборка контейнерного образа `localhost/kiwix` из Containerfile
4. Генерация `library.xml` из всех найденных ZIM-файлов с помощью `kiwix-manage`
5. Создание и запуск systemd user unit
6. Настройка nginx reverse proxy

## Зависимости

- Базовый образ: `docker.io/library/debian:13-slim`
- Роли: `base`, `podman`, `nginx`
