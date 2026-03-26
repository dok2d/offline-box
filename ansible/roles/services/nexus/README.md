# Nexus

Sonatype Nexus Repository Manager -- репозиторий для хранения и проксирования пакетов и артефактов. Поддерживает кеширующие прокси для APT (Debian), PyPI (Python) и Docker Registry, а также hosted-репозиторий для произвольных файлов.

## Переменные

| Переменная | Описание | Значение по умолчанию |
|-----------|----------|----------------------|
| `enable_nexus` | Включить/выключить сервис | `true` |
| `nexus_port` | Порт веб-интерфейса | `8004` |
| `nexus_data_dir` | Каталог для хранения данных | `/opt/nexus/data` |
| `nexus_config_dir` | Каталог конфигурации | `/opt/nexus/config` |
| `nexus_admin_password` | Пароль администратора | (из passwords.yml) |
| `nexus_jvm_heap` | Размер JVM heap | `1g` |
| `nexus_apt_proxy_url` | URL удалённого APT-репозитория для проксирования | `http://deb.debian.org/debian` |
| `nexus_apt_distribution` | Дистрибутив Debian для APT-прокси | `trixie` |
| `nexus_pypi_proxy_url` | URL удалённого PyPI для проксирования | `https://pypi.org` |
| `nexus_docker_proxy_url` | URL удалённого Docker Registry для проксирования | `https://registry-1.docker.io` |
| `nexus_docker_proxy_port` | Порт Docker-прокси репозитория | `5000` |

## Порт

Сервис слушает на `127.0.0.1:8004`. Доступен через nginx по пути `/nexus/`.
Docker-прокси доступен на порту `5000`.

## Данные

- **Данные**: `{{ opt_base }}/nexus/data` -- blob-хранилище, база данных, файл начального пароля `admin.password`
- **Конфигурация**: `{{ opt_base }}/nexus/config` -- Containerfile

## Инициализация

При первом развёртывании выполняются следующие действия:

1. Создание каталогов для данных и конфигурации
2. Сборка контейнерного образа `localhost/nexus` из Containerfile
3. Создание и запуск systemd user unit
4. Ожидание готовности Nexus (healthcheck по REST API)
5. Чтение начального пароля администратора из `admin.password`
6. Смена пароля администратора на значение `nexus_admin_password`
7. Включение анонимного доступа для чтения
8. Создание репозиториев:
   - **apt-debian** -- APT proxy для Debian
   - **pypi-proxy** -- PyPI proxy для Python-пакетов
   - **docker-proxy** -- Docker Registry proxy
   - **raw-hosted** -- hosted-репозиторий для произвольных файлов
9. Включение Docker Bearer Token realm
10. Настройка nginx reverse proxy

## Зависимости

- Базовый образ: `docker.io/library/debian:13-slim`
- Роли: `base`, `podman`, `nginx`
