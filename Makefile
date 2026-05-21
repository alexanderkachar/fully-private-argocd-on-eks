.PHONY: spin-up teardown-soft teardown-hard restore backup-gitea vpn-up vpn-down vpn-config ansible-setup

VENV    := .venv
REPO    := $(CURDIR)
ANSIBLE := $(REPO)/$(VENV)/bin/ansible-playbook
GALAXY  := $(REPO)/$(VENV)/bin/ansible-galaxy
PIP     := $(REPO)/$(VENV)/bin/pip
PYTHON  := python3

# All playbook runs cd into ansible/ so ansible.cfg + roles_path resolve.
RUN     := cd $(REPO)/ansible && $(ANSIBLE)

ansible-setup:
	$(PYTHON) -m venv $(VENV)
	$(PIP) install --upgrade pip
	$(PIP) install -r ansible/requirements.txt
	$(GALAXY) collection install -r ansible/requirements.yml

spin-up:
	$(RUN) playbooks/spin-up.yml

teardown-soft:
	$(RUN) playbooks/teardown-soft.yml

teardown-hard:
	$(RUN) playbooks/teardown-hard.yml -e confirm_hard=$(CONFIRM)

restore:
	$(RUN) playbooks/restore.yml $(if $(BACKUP_KEY),-e backup_key=$(BACKUP_KEY))

backup-gitea:
	$(RUN) playbooks/backup-gitea.yml

vpn-up:
	$(RUN) playbooks/vpn-up.yml

vpn-down:
	$(RUN) playbooks/vpn-down.yml

vpn-config:
	$(REPO)/scripts/vpn-config.sh
