.PHONY: spin-up teardown-soft teardown-hard restore backup-gitea vpn-up vpn-down

spin-up:
	./scripts/spin-up.sh

teardown-soft:
	./scripts/teardown-soft.sh

teardown-hard:
	./scripts/teardown-hard.sh

restore:
	./scripts/restore.sh

backup-gitea:
	./scripts/backup-gitea.sh

vpn-up:
	./scripts/vpn-toggle.sh up

vpn-down:
	./scripts/vpn-toggle.sh down
