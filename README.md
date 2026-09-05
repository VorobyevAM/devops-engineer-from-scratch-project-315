# Bulletin Board Service

[![CI](https://github.com/VorobyevAM/devops-engineer-from-scratch-project-315/actions/workflows/ci.yml/badge.svg)](https://github.com/VorobyevAM/devops-engineer-from-scratch-project-315/actions/workflows/ci.yml)

Форк учебного проекта Hexlet с доской объявлений на Spring Boot и React Admin. Репозиторий подготовлен для локальной контейнерной сборки: фронтенд собирается в Docker, попадает в Spring Boot JAR и дополнительно сохраняется в runtime image как `/app/static` для раздачи через Nginx.

## What Is Built

- Docker image repository: `ghcr.io/vorobyevam/devops-engineer-from-scratch-project-315`
- Recommended tags: `latest` and a commit-based tag like `sha-<git-sha>`
- Public application URL: `https://hexlet-vorobev.chickenkiller.com`
- Application container port: `8080`
- Management / Actuator port: `9090`
- GitHub Actions workflow: tests on `push`/`pull_request` for `main`, image publish to `GHCR` only on successful `push` to `main`
- Infrastructure target: Yandex Cloud VM configured by Ansible
- Domain name: `hexlet-vorobev.chickenkiller.com`

## Quick Start

Сборка образа:

```bash
make docker-build
```

Запуск контейнера:

```bash
make docker-run
```

Прямой запуск через Docker:

```bash
docker run --rm \
  --name project-devops-deploy \
  -p 8080:8080 \
  -p 9090:9090 \
  ghcr.io/vorobyevam/devops-engineer-from-scratch-project-315:latest
```

После старта приложение доступно по адресу `http://localhost:8080`, Swagger UI по `http://localhost:8080/swagger-ui/index.html`, а actuator endpoints по `http://localhost:9090/actuator`.

## Make Commands

- `make test` — запускает встроенные тесты Spring Boot
- `make run` — локальный запуск backend в dev-профиле
- `make build` — сборка Gradle-артефактов локально
- `make docker-build` — сборка production Docker-образа
- `make docker-run` — запуск контейнера из собранного образа
- `make ansible-install` — установка внешних Ansible-ролей
- `make ansible-check` — проверочный запуск плейбука в check-mode
- `make ansible-run` — применение плейбука к серверу
- `make deploy` — деплой Docker-контейнера на сервер с секретами из Ansible Vault
- `make rollback IMAGE_TAG=sha-<git-sha>` — откат на конкретный стабильный тег образа
- `make deploy-vault` — деплой с запросом пароля Ansible Vault
- `make deploy-no-vault` — деплой без Vault, если секреты уже переданы другим способом
- `make vault-create` — создание зашифрованного файла секретов Ansible Vault
- `make vault-edit` — редактирование секретов Ansible Vault

## Deployment Requirements

Local host:

- Docker with Buildx for local image builds
- Java 21 for local Gradle tests
- Node.js 24 and npm for frontend checks
- Ansible, installed roles and collections from `requirements.yml`
- SSH key with access to the target VM
- Ansible Vault password or `VAULT_PASSWORD_FILE`

Target host:

- Ubuntu 22.04/24.04 VM with a public IPv4 address
- At least 2 CPU cores, 2 GB RAM and 20 GB disk for Docker image pulls, PostgreSQL and the app
- Open inbound TCP ports `22`, `80` and `443`
- DNS A-record pointing the application domain to the VM public IP
- Outbound internet access for Docker/GHCR, apt packages, Let's Encrypt and S3

## Infrastructure

Минимальная инфраструктура ожидает одну ВМ в Yandex Cloud на Ubuntu 22.04/24.04 с публичным IP и SSH-доступом по ключу. Адрес целевой ВМ и SSH-пользователь описаны в `inventory.ini`; при переносе проекта на другой сервер измените `ansible_host` и при необходимости `ansible_user`.

Пример создания security group и ВМ через `yc`:

```bash
yc vpc security-group create \
  --name bulletin-board-sg \
  --network-name default \
  --rule "direction=ingress,port=22,protocol=tcp,v4-cidrs=[0.0.0.0/0]" \
  --rule "direction=ingress,port=80,protocol=tcp,v4-cidrs=[0.0.0.0/0]" \
  --rule "direction=ingress,port=443,protocol=tcp,v4-cidrs=[0.0.0.0/0]" \
  --rule "direction=egress,protocol=any,v4-cidrs=[0.0.0.0/0]"

yc compute instance create \
  --name bulletin-board \
  --hostname bulletin-board \
  --zone ru-central1-a \
  --memory 2G \
  --cores 2 \
  --network-interface subnet-name=default-ru-central1-a,nat-ip-version=ipv4,security-group-ids=<security-group-id> \
  --create-boot-disk image-folder-id=standard-images,image-family=ubuntu-2204-lts,size=20G,auto-delete=true \
  --ssh-key ~/.ssh/id_ed25519.pub
```

После создания проверьте SSH-доступ:

```bash
ssh yc-user@<vm-public-ip>
```

Подготовка сервера:

```bash
make ansible-install
make ansible-check
make ansible-run
```

Плейбук `playbook.yml` устанавливает базовые утилиты, Docker Engine, Docker Compose plugin, Nginx reverse proxy, добавляет SSH-пользователя в группу `docker` и настраивает UFW firewall. Публично открыты только TCP-порты `22`, `80` и `443`; приложение и actuator публикуются на `127.0.0.1` и доступны снаружи только через Nginx.

После применения инфраструктурного плейбука публичный вход в приложение доступен через Nginx и HTTPS:

```text
https://hexlet-vorobev.chickenkiller.com
```

Nginx проксирует динамические API-запросы к Spring Boot без кеширования, а статические frontend-файлы (`/assets/*`, `favicon.ico`, `manifest.json`, `robots.txt`) отдаёт напрямую из `/opt/bulletin-board/static` и кеширует на стороне клиента. Для файловых endpoint'ов `/api/files/view` и `/api/files/raw` настроен короткий proxy cache, чтобы повторные обращения к пользовательским файлам не били напрямую в приложение при каждом запросе.

Let's Encrypt сертификат выпускается через Certbot в `playbook.yml`. HTTP-порт `80` остаётся открытым для ACME challenge и редиректа на HTTPS. Продление сертификата выполняется системным `certbot.timer`, а deploy hook `/etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh` перезагружает Nginx после обновления сертификата.

Проверка HTTPS и автопродления на сервере:

```bash
curl -I https://hexlet-vorobev.chickenkiller.com
systemctl status certbot.timer
sudo certbot renew --dry-run --no-random-sleep-on-renew
```

## Deployment

Деплой выполняется отдельным playbook `deploy.yml`, который поднимает PostgreSQL, применяет Flyway-миграции, подтягивает Docker-образ приложения, запускает контейнер и ждёт готовности actuator health endpoint:

```bash
make deploy
```

Для деплоя конкретной версии используйте тег образа:

```bash
make deploy IMAGE_TAG=sha-abcdef1
```

Откат выполняется тем же механизмом через стабильный предыдущий тег:

```bash
make rollback IMAGE_TAG=sha-previous
```

Несекретные настройки лежат в `group_vars/app_servers.yml`. Секреты для production-профиля, базы данных, S3 или private registry нужно хранить в `group_vars/app_servers/vault.yml`, зашифрованном Ansible Vault:

```bash
cp group_vars/app_servers/vault.yml.example group_vars/app_servers/vault.yml
ansible-vault encrypt group_vars/app_servers/vault.yml
```

Минимальный набор секретов для PostgreSQL-контейнера на той же ВМ:

```yaml
postgres_user: bulletins
postgres_password: change-me
app_secret_env:
  SPRING_DATASOURCE_URL: jdbc:postgresql://bulletin-board-postgres:5432/bulletins
  SPRING_DATASOURCE_USERNAME: bulletins
  SPRING_DATASOURCE_PASSWORD: change-me
```

Для deploy с Vault:

```bash
make deploy
```

Для неинтерактивного запуска можно передать файл с паролем Vault:

```bash
make deploy VAULT_PASSWORD_FILE=/path/to/vault-password
```

Каталоги `/opt/bulletin-board/data`, `/opt/bulletin-board/logs`, `/opt/bulletin-board/migrations` и `/opt/bulletin-board/postgres` создаются на сервере автоматически. PostgreSQL хранит данные в `/opt/bulletin-board/postgres`, поэтому данные переживают перезапуск контейнеров. Приложение и БД общаются через приватную Docker-сеть `bulletin-board`; порт PostgreSQL наружу не публикуется.

Проверка persistence после деплоя:

```bash
ssh yc-user@62.84.122.118
docker restart bulletin-board
docker restart bulletin-board-postgres
docker ps
```

## S3 Object Storage

Production-профиль умеет хранить пользовательские файлы в S3-compatible storage. Для Yandex Object Storage создайте отдельный bucket, например:

```text
hexlet-vorobev-bulletin-files
```

Ручные шаги в Yandex Cloud:

1. Создайте bucket в Object Storage. Регион для Yandex Object Storage: `ru-central1`, endpoint: `https://storage.yandexcloud.net`.
2. Создайте service account для приложения, например `bulletin-board-storage`.
3. Выдайте service account минимальные права на bucket: чтение и запись объектов. Для учебного проекта подойдет роль `storage.editor` на конкретный bucket или каталог, если bucket-level policy недоступна.
4. Создайте static access key для service account и сохраните `Access Key ID` / `Secret Access Key` только в Ansible Vault или GitHub Secrets.
5. Если файлы должны открываться без presigned URL, настройте публичное чтение объектов и задайте `STORAGE_S3_CDNURL`. Если публичное чтение не нужно, не задавайте `STORAGE_S3_CDNURL`: приложение будет генерировать presigned ссылки.

S3-секреты добавляются в `group_vars/app_servers/vault.yml`:

```yaml
app_secret_env:
  SPRING_DATASOURCE_URL: jdbc:postgresql://bulletin-board-postgres:5432/bulletins
  SPRING_DATASOURCE_USERNAME: bulletins
  SPRING_DATASOURCE_PASSWORD: change-me
  STORAGE_S3_BUCKET: hexlet-vorobev-bulletin-files
  STORAGE_S3_REGION: ru-central1
  STORAGE_S3_ENDPOINT: https://storage.yandexcloud.net
  STORAGE_S3_ACCESSKEY: <access-key-id>
  STORAGE_S3_SECRETKEY: <secret-access-key>
```

После обновления Vault примените деплой:

```bash
make deploy
```

Проверка загрузки и получения ссылки:

```bash
curl -F "file=@/path/to/image.png" https://hexlet-vorobev.chickenkiller.com/api/files/upload
curl "https://hexlet-vorobev.chickenkiller.com/api/files/view?key=<key-from-upload-response>"
```

Если S3-переменные заполнены, приложение использует S3. Если они пустые, приложение переключается на локальное файловое хранилище внутри volume `/opt/bulletin-board/data`.

## DNS

Зарегистрируйте домен или бесплатный домен третьего уровня и создайте A-запись на публичный IP сервера:

```text
Type: A
Name: hexlet-vorobev.chickenkiller.com
Value: 62.84.122.118
TTL: 300
```

Если провайдер просит указать только поддомен, для `app.example.com` в поле `Name` обычно указывается `app`, а для корневого домена `example.com` — `@`.

Проверьте DNS после создания записи:

```bash
dig +short hexlet-vorobev.chickenkiller.com
nslookup hexlet-vorobev.chickenkiller.com
```

Ожидаемый результат:

```text
62.84.122.118
```

После изменения DNS-записи повторите деплой:

```bash
make deploy
```

Если pull из `GHCR` завершается ошибкой `denied`, проверьте два сценария:

1. Образ ещё не опубликован. Запушьте изменения в `main` и дождитесь успешного workflow `CI`, который публикует `latest` и `sha-<git-sha>`.
2. Package приватный. Сделайте package публичным в GitHub Packages или добавьте credentials в `group_vars/app_servers/vault.yml`:

```yaml
app_registry_username: your-github-login
app_registry_password: <github-token-with-read-packages>
```

После этого запускайте деплой с запросом пароля Vault:

```bash
make deploy-vault
```

## Notes

- Dockerfile использует multi-stage build: отдельно собирает фронтенд, затем backend и тесты, а в финальный образ кладёт только JAR.
- По умолчанию используется `dev` профиль с H2, поэтому контейнер стартует без внешней PostgreSQL.
- Исходный upstream-репозиторий `Hexlet-components/project-devops-deploy` остаётся read-only; все изменения ведутся только в этом форке.
- Workflow публикует теги `latest` и `sha-<7 символов коммита>` в `GHCR` через `GITHUB_TOKEN`, без хранения токенов и паролей в репозитории.
- Ansible-плейбук рассчитан на повторные запуски: пакеты, Docker, compose plugin, firewall rules и membership в `docker` group описаны декларативно.
- Деплой-плейбук тоже можно запускать повторно: PostgreSQL сохраняет данные в bind mount, Flyway применяет только новые миграции, образ подтягивается из registry, а контейнер приложения пересоздаётся только при изменении образа или параметров.
