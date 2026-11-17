SHELL := pwsh.exe
.SHELLFLAGS := -NoProfile -NoLogo -Command
.DEFAULT_GOAL := help
.PHONY: run live build test analyze format where help

# --- the Flutter SDK -------------------------------------------------------
# Neovim and other tools start make with a PATH that may not have Flutter on it,
# so the SDK is looked up in the places it is installed, and only then by name.
FLUTTER_PATHS := \
  H:/flutter/bin/flutter.bat \
  C:/tools/flutter/bin/flutter.bat \
  C:/flutter/bin/flutter.bat \
  D:/flutter/bin/flutter.bat \
  $(USERPROFILE)/flutter/bin/flutter.bat \
  $(LOCALAPPDATA)/flutter/bin/flutter.bat

FLUTTER_FOUND := $(firstword $(wildcard $(FLUTTER_PATHS)))

# The app takes the folder to manage as its first argument; `live` passes home.
HOME_ARG := $(subst \,/,$(USERPROFILE))

ifeq ($(strip $(FLUTTER_FOUND)),)
FLUTTER := flutter
DART := dart
else
FLUTTER := $(FLUTTER_FOUND)
DART := $(patsubst %flutter.bat,%dart.bat,$(FLUTTER))
endif

##@ app

run: ## run the app against the current folder
	& "$(FLUTTER)" run -d windows

live: ## run the app on the home folder, everything also in out/live.log
	New-Item -ItemType Directory -Force out | Out-Null; $$env:PURRAGE_BUILD = 'live'; & "$(FLUTTER)" run -d windows -a "$(HOME_ARG)" 2>&1 | Tee-Object -FilePath out/live.log

build: ## release build of the Windows app
	& "$(FLUTTER)" build windows

##@ checks

test: ## the whole test suite, then check that %TEMP% has no new purrage_* folder
	$$count = { @(Get-ChildItem $$env:TEMP -Directory -Filter 'purrage_*').Count }; $$before = & $$count; & "$(FLUTTER)" test --timeout 22s; $$code = $$LASTEXITCODE; $$after = & $$count; if ($$after -gt $$before) { Write-Output ('    left {0} purrage_* folder(s) in %TEMP%' -f ($$after - $$before)); exit 1 }; Write-Output ('unchanged {0} purrage_* folder(s) in %TEMP%' -f $$after); exit $$code

analyze: ## static analysis
	& "$(FLUTTER)" analyze

format: ## format lib and test
	& "$(DART)" format lib test

##@ other

where: ## which Flutter and Dart the targets will use
	@Write-Output "flutter: $(FLUTTER)"
	@Write-Output "dart:    $(DART)"

help: ## this list
	@Get-Content $(firstword $(MAKEFILE_LIST)) | Select-String -Pattern '^(##@|[a-z-]+:.*## )' | ForEach-Object { $$l = $$_.Line; if ($$l -like '##@*') { ''; $$l.Substring(4) } else { $$p = $$l -split ':.*## ', 2; '  {0,-8} {1}' -f $$p[0], $$p[1] } }
