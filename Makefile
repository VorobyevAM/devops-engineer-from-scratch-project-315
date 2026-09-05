IMAGE_NAME ?= ghcr.io/vorobyevam/devops-engineer-from-scratch-project-315
IMAGE_TAG ?= latest
CONTAINER_NAME ?= project-devops-deploy
APP_PORT ?= 8080
MANAGEMENT_PORT ?= 9090
VAULT_PASSWORD_FILE ?=
VAULT_ARGS = $(if $(VAULT_PASSWORD_FILE),--vault-password-file $(VAULT_PASSWORD_FILE),--ask-vault-pass)

test:
	./gradlew test

start: run

run:
	./gradlew bootRun

update-gradle:
	./gradlew wrapper --gradle-version 9.7.0

install:
	./gradlew dependencies

build:
	./gradlew build

docker-build:
	docker build -t $(IMAGE_NAME):$(IMAGE_TAG) .

docker-run:
	docker run --rm --name $(CONTAINER_NAME) -p $(APP_PORT):8080 -p $(MANAGEMENT_PORT):9090 $(IMAGE_NAME):$(IMAGE_TAG)

docker-start: docker-run

ansible-install:
	ansible-galaxy role install -r requirements.yml -p .ansible/roles
	ansible-galaxy collection install -r requirements.yml -p .ansible/collections

ansible-check:
	ansible-playbook playbook.yml $(VAULT_ARGS) --check --diff

ansible-run:
	ansible-playbook playbook.yml $(VAULT_ARGS)

ansible-ping:
	ansible app_servers -m ping

deploy:
	ansible-playbook deploy.yml $(VAULT_ARGS) -e app_image_tag=$(IMAGE_TAG)

rollback: deploy

deploy-vault:
	ansible-playbook deploy.yml $(VAULT_ARGS) -e app_image_tag=$(IMAGE_TAG)

deploy-no-vault:
	ansible-playbook deploy.yml -e app_image_tag=$(IMAGE_TAG)

vault-create:
	cp group_vars/app_servers/vault.yml.example group_vars/app_servers/vault.yml
	ansible-vault encrypt group_vars/app_servers/vault.yml

vault-edit:
	ansible-vault edit group_vars/app_servers/vault.yml

.PHONY: build test start run install docker-build docker-run docker-start update-gradle ansible-install ansible-check ansible-run ansible-ping deploy rollback deploy-vault deploy-no-vault vault-create vault-edit
