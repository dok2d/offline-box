# Аудит архитектуры и DevOps — Offline Box

**Дата:** 2026-03-22
**Область:** Архитектура, безопасность, DevOps, надёжность, производительность

---

## 1. Общая оценка

Проект представляет собой зрелую IaC-инфраструктуру для развёртывания 14 self-hosted сервисов на одном сервере с Ansible + rootless Podman + nginx reverse proxy. Архитектура грамотно спроектирована для offline-сценария. Ниже — выявленные проблемы, ранжированные по критичности.

---

## 2. КРИТИЧЕСКИЕ проблемы (P0)

### 2.1. Секреты генерируются заново при каждом запуске плейбука

**Файл:** `ansible/group_vars/passwords.yml`

Все пароли используют `lookup('password', '/dev/null ...)` — это генерирует **новый** пароль при каждом запуске Ansible. После повторного `ansible-playbook` все сервисы получат новые пароли, а старые данные станут недоступны.

```yaml
# ПРОБЛЕМА: /dev/null = каждый раз новый пароль
transmission_rpc_password: "{{ lookup('password', '/dev/null chars=ascii_letters,digits length=24') }}"
```

**Рекомендация:** Использовать файловый кэш паролей:
```yaml
transmission_rpc_password: "{{ lookup('password', 'credentials/transmission_rpc length=24 chars=ascii_letters,digits') }}"
```
Либо использовать `ansible-vault` для хранения зафиксированных секретов.

### 2.2. Нет .gitignore — риск утечки секретов

В репозитории **отсутствует `.gitignore`**. Если пароли будут сохранены в файлы (как рекомендовано выше) или появятся `.env`-файлы, они могут случайно попасть в git.

**Рекомендация:** Создать `.gitignore`:
```
credentials/
*.retry
*.env
.vault_pass
```

### 2.3. BigBlueButton — захардкоженный пароль БД

**Файл:** `ansible/roles/services/bigbluebutton/templates/Containerfile.j2:57`

```dockerfile
psql --command "CREATE USER bigbluebutton WITH PASSWORD 'bbb_password';"
```

Пароль `bbb_password` вшит в образ контейнера. Хотя PostgreSQL работает внутри контейнера, это нарушает принцип управления секретами.

**Рекомендация:** Параметризировать через Jinja2-переменную `{{ bigbluebutton_db_password }}`.

### 2.4. Vaultwarden — ADMIN_TOKEN передаётся через CLI-аргументы

**Файл:** `ansible/roles/services/vaultwarden/templates/vaultwarden.service.j2:20`

```
-e ADMIN_TOKEN={{ vaultwarden_admin_token }}
```

Токен виден в `ps aux`, `systemctl status`, journalctl и `/proc/*/cmdline`. Это **критическая утечка** для менеджера паролей.

**Рекомендация:** Использовать `--env-file` или Podman secrets:
```
--secret vaultwarden_admin_token,type=env,target=ADMIN_TOKEN
```

Аналогичная проблема касается **всех сервисов** с `-e SECRET_KEY=...` в systemd unit (Paperless-NGX, Gitea и др.).

---

## 3. ВЫСОКИЙ приоритет (P1)

### 3.1. Nextcloud на встроенном PHP dev-сервере

**Файл:** `ansible/roles/services/nextcloud/templates/Containerfile.j2:18`

```dockerfile
ENTRYPOINT ["php", "-S", "0.0.0.0:{{ nextcloud_port }}", "-t", "/opt/nextcloud"]
```

PHP built-in server **не предназначен для production** (однопоточный, нет обработки concurrency, нет защит). Nextcloud официально требует Apache/nginx + php-fpm.

**Рекомендация:** Заменить на `php-fpm` + nginx или Apache внутри контейнера.

### 3.2. Nextcloud скачивает "latest" без фиксации версии

**Файл:** `ansible/roles/services/nextcloud/templates/Containerfile.j2:9`

```dockerfile
RUN curl -fsSL https://download.nextcloud.com/server/releases/latest.tar.bz2 | tar xj -C /opt
```

Нет фиксированной версии — невоспроизводимые билды. При очередном build может прийти мажорная версия с breaking changes.

**Рекомендация:** Использовать переменную `nextcloud_version` и конкретный URL с версией.

### 3.3. Gitea — открытая регистрация и анонимный доступ

**Файл:** `ansible/roles/services/gitea/templates/app.ini.j2:20-21`

```ini
DISABLE_REGISTRATION = false
REQUIRE_SIGNIN_VIEW = false
```

На домашнем сервере регистрация должна быть закрыта по умолчанию, а просмотр — только для авторизованных.

**Рекомендация:**
```ini
DISABLE_REGISTRATION = {{ gitea_disable_registration | default(true) }}
REQUIRE_SIGNIN_VIEW = {{ gitea_require_signin | default(true) }}
```

### 3.4. Нет бэкапов данных

Нигде в проекте нет стратегии резервного копирования. 14 сервисов хранят данные в `/opt/<service>/data/`, но нет:
- Cron-задач для бэкапов
- Скриптов для создания снапшотов
- Ротации бэкапов

**Рекомендация:** Добавить роль `backup` с:
- Периодическим копированием `/opt/*/data/`
- Опциональной синхронизацией через Syncthing на внешний носитель
- Дампом SQLite/PostgreSQL БД перед копированием

### 3.5. Нет мониторинга и алертов

Dashboard проверяет health только из браузера клиента. Нет серверного мониторинга:
- Нет проверки дискового пространства
- Нет алертов при падении сервиса
- Нет метрик по использованию ресурсов

**Рекомендация:** Добавить systemd-таймер с проверкой `podman healthcheck` и отправкой уведомлений (email/telegram) при сбоях.

### 3.6. BigBlueButton Containerfile — ненадёжные билды

**Файл:** `ansible/roles/services/bigbluebutton/templates/Containerfile.j2`

Множественные `|| true` маскируют ошибки сборки:
```dockerfile
RUN npm install -g etherpad-lite || true     # строка 52
RUN ... wget ... || true                      # строка 49
RUN ... && /etc/init.d/postgresql stop || true  # строка 59
```

Контейнер может быть собран без ключевых компонентов, и это не будет обнаружено.

**Рекомендация:** Убрать `|| true` и обрабатывать ошибки явно. Использовать multi-stage build.

---

## 4. СРЕДНИЙ приоритет (P2)

### 4.1. Нет CI/CD пайплайна

Отсутствует автоматизация:
- Нет GitHub Actions/GitLab CI
- Нет линтинга Ansible (`ansible-lint`)
- Нет валидации шаблонов
- Нет smoke-тестов после деплоя

**Рекомендация:** Добавить минимальный CI:
```yaml
# .github/workflows/lint.yml
- ansible-lint ansible/playbook.yml
- yamllint ansible/
```

### 4.2. Контейнеры принудительно пересобираются при каждом деплое

**Файл:** Все service tasks содержат `force: true`:
```yaml
- containers.podman.podman_image:
    force: true  # всегда пересборка
```

Это увеличивает время деплоя и не позволяет использовать кэш.

**Рекомендация:** Использовать hash Containerfile как тег вместо `force: true`, чтобы пересборка происходила только при изменениях.

### 4.3. Paperless-NGX — Redis работает без пароля внутри контейнера

**Файл:** `ansible/roles/services/paperless-ngx/files/entrypoint.sh:3`

```bash
redis-server --daemonize yes --port 6379 --bind 127.0.0.1 --dir /run/redis
```

Redis без пароля. Хотя bind на 127.0.0.1, при любом SSRF или container escape это может стать вектором атаки.

### 4.4. Отсутствует read-only rootfs для контейнеров

Systemd unit'ы не используют `--read-only` для файловых систем контейнеров. Это снизило бы поверхность атаки.

**Рекомендация:** Добавить `--read-only` + `--tmpfs /tmp:rw,size=100m` где возможно.

### 4.5. RSA 2048 для TLS-сертификата

**Файл:** `ansible/roles/nginx/tasks/main.yml:29`

```
-newkey rsa:2048
```

2048-бит RSA — минимально допустимый. Для self-signed certs лучше использовать ECDSA (быстрее, безопаснее):
```
openssl ecparam -genkey -name prime256v1 | openssl req ...
```

### 4.6. Нет ротации логов nginx

Логи nginx (`/var/log/nginx/`) будут расти неограниченно. Не установлен `logrotate` и нет конфигурации ротации.

**Рекомендация:** Добавить задачу для настройки logrotate в роли nginx или base.

### 4.7. net.ipv4.ip_unprivileged_port_start=80 — ослабление безопасности

**Файл:** `ansible/roles/base/tasks/main.yml:32`

Это позволяет **любому** непривилегированному процессу слушать порты >= 80. Если на сервере появится другой пользователь, он может подменить nginx.

**Рекомендация:** Убрать этот параметр, т.к. nginx работает от root и не нуждается в нём. Если нужен для Podman — использовать `net.ipv4.ip_unprivileged_port_start=1024` (стандарт) и маппить на высокие порты.

### 4.8. Gitea SSH порт слушает на 0.0.0.0

**Файл:** `ansible/roles/services/gitea/templates/gitea.service.j2:16`

```
-p {{ gitea_ssh_port }}:2222
```

В отличие от HTTP-портов, SSH-порт не привязан к `listen_addr` (127.0.0.1). Он слушает на всех интерфейсах — ожидаемо, но не задокументировано и не параметризировано.

---

## 5. НИЗКИЙ приоритет (P3)

### 5.1. DH parameters 2048 бит

`ssl_dhparam` генерируется на 2048 бит. Рекомендуется 4096 для TLS 1.2. Для TLS 1.3 DH params вообще не нужны.

### 5.2. Dashboard XSS-уязвимость (теоретическая)

**Файл:** `ansible/roles/nginx/templates/dashboard.html.j2:184`

```javascript
a.innerHTML = '<h2>' + s.name + '</h2>' + ...
```

Данные из Ansible (имена сервисов) вставляются через `innerHTML`. Если имя сервиса содержит HTML — возможен XSS. Риск низкий (данные контролируются администратором), но лучше использовать `textContent`.

### 5.3. Нет описания зависимостей Ansible (requirements.yml)

Проект использует коллекции `containers.podman`, `community.general`, `ansible.posix`, `ansible.utils`, но нет файла `requirements.yml` для их установки.

**Рекомендация:**
```yaml
# ansible/requirements.yml
collections:
  - name: containers.podman
  - name: community.general
  - name: ansible.posix
  - name: ansible.utils
```

### 5.4. Идемпотентность — shell-задача Kiwix library.xml

**Файл:** `ansible/roles/services/kiwix/tasks/main.yml:50`

```yaml
ansible.builtin.shell: |
    set -e
    rm -f {{ kiwix_data_dir }}/library.xml
    ...
  changed_when: kiwix_library.rc == 0
```

`changed_when: rc == 0` — всегда `changed`. Нарушает идемпотентность Ansible.

### 5.5. `client_max_body_size 0` в глобальном nginx

**Файл:** `ansible/roles/nginx/templates/nginx.conf.j2:42`

Значение `0` = неограниченный размер тела запроса. Хотя per-location лимиты есть для некоторых сервисов, сервисы без явного `client_max_body_size` уязвимы к DoS через загрузку больших файлов.

**Рекомендация:** Установить глобальный лимит (например, `100m`) и переопределять в location.

---

## 6. Архитектурные рекомендации

| Область | Текущее состояние | Рекомендация |
|---------|------------------|--------------|
| Single point of failure | Один сервер, 14 сервисов | Документировать DR-процедуру, добавить бэкапы |
| Обновления | Нет стратегии обновлений | Добавить переменные версий для всех сервисов, тегировать образы |
| Rollback | Невозможен | Хранить предыдущие образы (`podman tag ... :prev`) |
| Масштабирование | Monolith | Приемлемо для home server, но стоит документировать лимиты ресурсов |
| Тестирование | Отсутствует | Molecule + Testinfra для ролей |
| Документация | README.md на русском | Добавить ADR (Architecture Decision Records) |

---

## 7. Матрица приоритетов

| # | Проблема | Критичность | Сложность | Приоритет |
|---|---------|-------------|-----------|-----------|
| 2.1 | Пароли регенерируются | Критическая | Низкая | P0 |
| 2.2 | Нет .gitignore | Критическая | Низкая | P0 |
| 2.3 | BBB захардкоженный пароль | Критическая | Низкая | P0 |
| 2.4 | Секреты в CLI-аргументах | Критическая | Средняя | P0 |
| 3.1 | Nextcloud на PHP dev-server | Высокая | Средняя | P1 |
| 3.2 | Nextcloud без фиксации версии | Высокая | Низкая | P1 |
| 3.3 | Gitea открытая регистрация | Высокая | Низкая | P1 |
| 3.4 | Нет бэкапов | Высокая | Средняя | P1 |
| 3.5 | Нет мониторинга | Высокая | Средняя | P1 |
| 3.6 | BBB ненадёжные билды | Высокая | Средняя | P1 |
| 4.1 | Нет CI/CD | Средняя | Средняя | P2 |
| 4.2 | force rebuild | Средняя | Низкая | P2 |
| 4.3 | Redis без пароля | Средняя | Низкая | P2 |
| 4.4 | Нет read-only rootfs | Средняя | Средняя | P2 |
| 4.5 | RSA 2048 | Средняя | Низкая | P2 |
| 4.6 | Нет ротации логов | Средняя | Низкая | P2 |
| 4.7 | unprivileged_port_start=80 | Средняя | Низкая | P2 |
| 5.1-5.5 | Мелкие улучшения | Низкая | Низкая | P3 |

---

## 8. Что сделано хорошо

- **Rootless Podman** — отличный выбор для безопасности
- **cap-drop=ALL + no-new-privileges** — во всех systemd unit'ах
- **Security headers** — HSTS, X-Content-Type-Options, CSP
- **Rate limiting** — три зоны с разными лимитами
- **Firewall (UFW)** — deny по умолчанию, только нужные порты
- **Сервисы на loopback** — все порты на 127.0.0.1, nginx как единая точка входа
- **Ресурсные лимиты** — MemoryMax/CPUQuota в systemd unit'ах
- **Service registry pattern** — единый словарь сервисов
- **Условное включение** — каждый сервис можно отключить через `enable_*`
- **Nginx validate перед reload** — handler проверяет конфиг
- **Dashboard с health checks** — визуальный статус всех сервисов
- **Стандартизированная структура ролей** — единообразие между 14 сервисами
