# MaStR monorepo :: ETL / WORK Shiny convenience targets (run from repo root)
# Most users never run these. CI (.github/workflows/nightly-etl.yml) runs them.

PY  ?= python3
VENV := WORK/etl/.venv
BIN  := $(VENV)/bin

DATA_DIR ?= data
WORK_DIR ?= $(DATA_DIR)/work
OUT_DIR  ?= $(DATA_DIR)/parquet
DUCKDB   ?= $(DATA_DIR)/mastr.duckdb
RELEASE_TAG ?= data-$(shell date -u +%Y-%m-%d)

.PHONY: help venv install download parse duckdb aggregates all clean \
        schema-check publish test lint shiny-lint shinylive

help:
	@echo "MaStR monorepo targets (WORK/etl):"
	@echo "  make venv          - create Python virtualenv in WORK/etl/.venv"
	@echo "  make install       - install Python deps"
	@echo "  make download      - fetch MaStR ZIP into $(WORK_DIR)"
	@echo "  make parse         - XML -> Parquet in $(OUT_DIR)"
	@echo "  make duckdb        - build $(DUCKDB) with views + indices"
	@echo "  make aggregates    - pre-roll small aggregates for shinylive"
	@echo "  make all           - download + parse + duckdb + aggregates"
	@echo "  make publish       - upload artifacts to GitHub Release $(RELEASE_TAG)"
	@echo "  make schema-check  - diff current XML schema vs committed snapshot"
	@echo "  make test          - run pytest"
	@echo "  make shinylive     - build WebAssembly Shiny site (gh-pages)"
	@echo "  make clean         - remove $(DATA_DIR)"

venv:
	$(PY) -m venv $(VENV)
	$(BIN)/pip install -U pip wheel

install: venv
	$(BIN)/pip install -e WORK/etl

download:
	$(BIN)/python -m mastr_etl.download --out $(WORK_DIR)

parse:
	$(BIN)/python -m mastr_etl.parse --in $(WORK_DIR) --out $(OUT_DIR)

duckdb:
	$(BIN)/python -m mastr_etl.build_duckdb --parquet $(OUT_DIR) --out $(DUCKDB)

aggregates:
	$(BIN)/python -m mastr_etl.aggregates --duckdb $(DUCKDB) --out $(OUT_DIR)/aggregates

all: download parse duckdb aggregates

schema-check:
	$(BIN)/python -m mastr_etl.schema_diff --work $(WORK_DIR) --snapshot WORK/etl/schema_snapshot.json

publish:
	$(BIN)/python -m mastr_etl.publish --tag $(RELEASE_TAG) --parquet $(OUT_DIR) --duckdb $(DUCKDB)

test:
	$(BIN)/pytest WORK/etl/tests -v

lint:
	$(BIN)/ruff check WORK/etl

shinylive:
	Rscript -e 'shinylive::export("WORK/shiny", "shinylive-site", subdir = "apps")'

clean:
	rm -rf $(DATA_DIR)
