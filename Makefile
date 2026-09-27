.PHONY: help up down plan test drill lint app-test diagram
help: ## list targets
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-10s %s\n", $$1, $$2}'
up: ## build EVERYTHING end to end, run a release through prod, and prove it
	./scripts/up.sh
down: ## delete EVERYTHING this repo created (PURGE=1 also drops the state)
	./scripts/down.sh $(if $(PURGE),--purge,)
plan: ## terraform plan
	./scripts/up.sh --plan
test: ## live test suite against the running system
	./scripts/test.sh
drill: ## the bad-release drill: ship a faulty release, watch it get caught, roll back
	./scripts/demo-bad-release.sh
app-test: ## unit tests
	.venv/bin/pytest -q
lint: ## ruff, terraform fmt + validate, bash syntax
	.venv/bin/ruff check app && .venv/bin/ruff format --check app
	terraform -chdir=terraform fmt -check -recursive && terraform -chdir=terraform validate
	shellcheck -S warning -x scripts/*.sh && bash -n scripts/*.sh
diagram: ## regenerate docs/img/architecture.{svg,png}
	python3 docs/diagrams/architecture.py && python3 docs/diagrams/render.py docs/img/architecture.svg docs/img/architecture.png
