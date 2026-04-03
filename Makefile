.PHONY: help up down reset pipeline test lint clean

PYTHON := python3
SRC    := src/pipeline.py

help:
	@echo ""
	@echo "Aviation Safety Pipeline — Make targets"
	@echo "----------------------------------------"
	@echo "  make up        Start PostgreSQL via Docker Compose"
	@echo "  make down      Stop PostgreSQL (keeps data)"
	@echo "  make reset     Stop PostgreSQL AND wipe data volume"
	@echo "  make install   Install Python dependencies"
	@echo "  make pipeline  Run full pipeline (bronze → silver → gold)"
	@echo "  make bronze    Run bronze ingestion only"
	@echo "  make silver    Run bronze + silver"
	@echo ""

# ── Docker ────────────────────────────────────────────────────────

up:
	docker-compose up -d
	@echo "Waiting for PostgreSQL to be healthy..."
	@until docker-compose ps | grep -q "healthy"; do sleep 2; done
	@echo "PostgreSQL is ready."

down:
	docker-compose down

reset:
	docker-compose down -v
	@echo "Data volume removed."

# ── Python ───────────────────────────────────────────────────────

install:
	pip install -r requirements.txt

pipeline:
	cd src && $(PYTHON) pipeline.py --stage gold

bronze:
	cd src && $(PYTHON) pipeline.py --stage bronze

silver:
	cd src && $(PYTHON) pipeline.py --stage silver