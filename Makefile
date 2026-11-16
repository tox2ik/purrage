SHELL := pwsh.exe
.SHELLFLAGS := -NoProfile -NoLogo -Command
.DEFAULT_GOAL := help

##@ app

run: ## run the app against the current folder
	flutter run -d windows

live: ## run the app, everything also written to out/live.log
	New-Item -ItemType Directory -Force out | Out-Null; flutter run -d windows 2>&1 | Tee-Object -FilePath out/live.log

##@ checks

test: ## the whole test suite, one file at a time
	flutter test

analyze: ## static analysis
	flutter analyze

format: ## format lib and test
	dart format lib test

##@ help

help: ## this list
	@Get-Content $(firstword $(MAKEFILE_LIST)) | Select-String -Pattern '^(##@|[a-z-]+:.*## )' | ForEach-Object { $$l = $$_.Line; if ($$l -like '##@*') { ''; $$l.Substring(4) } else { $$p = $$l -split ':.*## ', 2; '  {0,-8} {1}' -f $$p[0], $$p[1] } }
