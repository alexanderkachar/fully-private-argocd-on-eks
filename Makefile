.PHONY: spin-up teardown-soft teardown-hard restore backup-gitea vpn-up vpn-down ansible-setup

VENV       := .venv
ANSIBLE    := $(VENV)/bin/ansible-playbook
GALAXY     := $(VENV)/bin/ansible-galaxy
PIP        := $(VENV)/bin/pip
PYTHON     := python3
PLAYBOOKS  := ansible/playbooks

ansible-setup:
	$(PYTHON) -m venv $(VENV)
	$(PIP) install --upgrade pip
	$(PIP) install -r ansible/requirements.txt
	$(GALAXY) collection install -r ansible/requirements.yml

spin-up:
	$(ANSIBLE) $(PLAYBOOKS)/spin-up.yml

teardown-soft:
	$(ANSIBLE) $(PLAYBOOKS)/teardown-soft.yml

teardown-hard:
	$(ANSIBLE) $(PLAYBOOKS)/teardown-hard.yml -e confirm_hard=$(CONFIRM)

restore:
	$(ANSIBLE) $(PLAYBOOKS)/restore.yml $(if $(BACKUP_KEY),-e backup_key=$(BACKUP_KEY))

backup-gitea:
	$(ANSIBLE) $(PLAYBOOKS)/backup-gitea.yml

vpn-up:
	$(ANSIBLE) $(PLAYBOOKS)/vpn-up.yml

vpn-down:
	$(ANSIBLE) $(PLAYBOOKS)/vpn-down.yml
