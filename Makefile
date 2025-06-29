default: run

help: # with thanks to Ben Rady
	@grep -E '^[0-9a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

# If you see "node-not-found" then you need to depend on node-installed.
NODE:=node-not-found
NPM:=npm-not-found
NODE_MODULES:=./node_modules/.npm-updated
NODE_ARGS?=
TS_NODE_ARGS:=--no-warnings=ExperimentalWarning --import=tsx

# All file paths that are not .ts files that should be watched for changes if launched with watch.
FILEWATCHER_ARGS:=--watch --include "etc/config/*"

# These 'find' scripts cache their results in a dotfile.
# Doing it this way instead of NODE:=$(shell etc/script/find-node) means
# if they fail, they stop the make process. As best I can tell there's no
# way to get make to fail if a sub-shell command fails.
.node-bin: etc/scripts/find-node
	@etc/scripts/find-node .node-bin

# All targets that need node must depend on this to ensure the NODE variable
# is appropriately set, and that PATH is updated.
.PHONY: node-installed
node-installed: .node-bin
	@$(eval NODE:=$(shell cat .node-bin))
	@$(eval NPM:=$(shell dirname $(shell cat .node-bin))/npm)
	@$(eval PATH=$(shell dirname $(realpath $(NODE))):$(PATH))

.PHONY: info
info: node-installed ## print out some useful variables
	@echo Using node from $(NODE)
	@echo Using npm from $(NPM)
	@echo PATH is $(PATH)

# disassemblers are needed for local deploys: #4225
.PHONY: scripts
scripts:
	mkdir -p out/dist/etc/scripts/disasms
	rsync -r -u etc/scripts/disasms/* out/dist/etc/scripts/disasms

.PHONY: prereqs
prereqs: $(NODE_MODULES)

$(NODE_MODULES): package.json package-lock.json | node-installed
	$(NPM) clean-install $(NPM_FLAGS)
	@rm -rf node_modules/.cache/esm/*
	@touch $@

.PHONY: lint
lint: $(NODE_MODULES)  ## Checks if the source currently matches code conventions
	$(NPM) run ts-check
	$(NPM) run lint-check

.PHONY: lint-fix
lint-fix: $(NODE_MODULES)  ## Checks if everything matches code conventions & fixes those which are trivial to do so
	$(NPM) run lint

.PHONY: test
test: $(NODE_MODULES)  ## Runs the tests
	$(NPM) run test
	@echo Tests pass

.PHONY: test-min
test-min: $(NODE_MODULES)  ## Runs the minimal tests
	$(NPM) run test-min
	@echo Tests pass

.PHONY: check
check: $(NODE_MODULES) lint test  ## Runs all checks required before committing (fixing trivial things automatically)

.PHONY: check-frontend-imports
check-frontend-imports: node-installed  ## Check that frontend doesn't import from backend
	@$(NODE) ./etc/scripts/check-frontend-imports.js

.PHONY: pre-commit
pre-commit: $(NODE_MODULES) test-min lint check-frontend-imports

.PHONY: clean
clean:  ## Cleans up everything
	rm -rf node_modules .*-updated .*-bin out

.PHONY: prebuild
prebuild: prereqs scripts
	$(NPM) run webpack
	$(NPM) run ts-compile

.PHONY: run-only
run-only: node-installed  ## Runs the site like it runs in production without building it
	env NODE_ENV=production $(NODE) $(NODE_ARGS) ./out/dist/app.js --static ./out/webpack/static $(EXTRA_ARGS)

.PHONY: run
run:  ## Runs the site like it runs in production
	$(MAKE) prebuild
	$(MAKE) run-only

.PHONY: dev
dev: prereqs ## Runs the site as a developer; including live reload support and installation of git hooks
	NODE_OPTIONS="$(TS_NODE_ARGS) $(NODE_ARGS)" ./node_modules/.bin/tsx watch $(FILEWATCHER_ARGS) ./app.ts $(EXTRA_ARGS)

.PHONY: gpu-dev
gpu-dev: prereqs ## Runs the site as a developer; including live reload support and installation of git hooks
	NODE_OPTIONS="$(TS_NODE_ARGS) $(NODE_ARGS)" ./node_modules/.bin/tsx watch $(FILEWATCHER_ARGS) ./app.ts --env gpu $(EXTRA_ARGS)

.PHONY: debug
debug: prereqs ## Runs the site as a developer with full debugging; including live reload support and installation of git hooks
	NODE_OPTIONS="$(TS_NODE_ARGS) $(NODE_ARGS) --inspect 9229" ./node_modules/.bin/tsx watch $(FILEWATCHER_ARGS) ./app.ts --debug $(EXTRA_ARGS)

.PHONY:
asm-docs:
	$(MAKE) -C etc/scripts/docenizers || ( \
		echo "==============================================================================="; \
		echo "One of the docenizers failed to run, make sure you have installed the necessary"; \
		echo "dependencies: pip3 install beautifulsoup4 pdfminer.six && npm install"; \
		echo "==============================================================================="; \
		exit 1 \
	)
