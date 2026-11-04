# mango for macOS
PREFIX        ?= $(HOME)/.local
APP_DIR       ?= /Applications
CONFIG        ?= release
# Set to a codesigning identity (e.g. "Apple Development: you@example.com") to keep the
# Accessibility permission stable across rebuilds. "-" = ad-hoc (permission must be
# re-granted after every rebuild).
CODESIGN_IDENTITY ?= -
# Extra codesign flags, e.g. CODESIGN_FLAGS="--options runtime".
CODESIGN_FLAGS    ?=
# Optional per-machine settings (not in git), e.g. CODESIGN_IDENTITY=aerospace-codesign-certificate
-include local.mk

# Extra `swift build` arguments, e.g. SWIFT_FLAGS="--scratch-path /tmp/mango-build".
SWIFT_FLAGS   ?=

# Where SwiftPM puts the products. Asked from SwiftPM (recursive variable, only expanded by
# recipes that run after `build`) so SWIFT_FLAGS and non-default build layouts work.
BUILD_DIR      = $(shell swift build -c $(CONFIG) $(SWIFT_FLAGS) --show-bin-path)
# The app: Mango Chutney, mango for macOS. Its programs keep mango's names (mango, mmsg).
APP_NAME      := Mango Chutney.app
APP           := dist/$(APP_NAME)
# Before the rename: removed by install, its launch agent too.
OLD_APP       := Mango.app
OLD_LABEL     := dev.mango.wm
LABEL         := dev.mangochutney

.PHONY: all build app test install uninstall run clean check mango-diff readme-tables config-diff mac-config release cask

all: app

build:
	swift build -c $(CONFIG) $(SWIFT_FLAGS) --product mango
	swift build -c $(CONFIG) $(SWIFT_FLAGS) --product mmsg

app: build
	rm -rf "$(APP)"
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	cp Resources/Info.plist "$(APP)/Contents/Info.plist"
	cp $(BUILD_DIR)/mango "$(APP)/Contents/MacOS/mango"
	cp $(BUILD_DIR)/mmsg "$(APP)/Contents/MacOS/mmsg"
	cp Resources/config.conf "$(APP)/Contents/Resources/config.conf"
	cp Resources/config-mac.conf "$(APP)/Contents/Resources/config-mac.conf"
	cp Resources/start.conf "$(APP)/Contents/Resources/start.conf"
	cp Resources/mango.svg "$(APP)/Contents/Resources/mango.svg"
	@if [ "$(CODESIGN_IDENTITY)" != "-" ] && ! security find-identity -p codesigning | grep -qF '"$(CODESIGN_IDENTITY)"'; then \
		echo "error: no code signing identity named \"$(CODESIGN_IDENTITY)\". Available:"; \
		security find-identity -p codesigning | grep '"' || echo "  (none: create one in Keychain Access › Certificate Assistant)"; \
		exit 1; \
	fi
	@# mmsg is a second executable in the bundle: signed on its own, before the bundle.
	codesign --force --sign "$(CODESIGN_IDENTITY)" $(CODESIGN_FLAGS) --identifier $(LABEL).mmsg "$(APP)/Contents/MacOS/mmsg"
	codesign --force --sign "$(CODESIGN_IDENTITY)" $(CODESIGN_FLAGS) --identifier $(LABEL) "$(APP)"
	@echo "built $(APP)"

# XCTest ships with Xcode, not with the Command Line Tools.
XCODE_DEV := $(shell test -d /Applications/Xcode.app && echo /Applications/Xcode.app/Contents/Developer)

test:
	$(if $(XCODE_DEV),DEVELOPER_DIR=$(XCODE_DEV)) swift test

# Validate the shipped default config with the freshly built parser.
check: build
	$(BUILD_DIR)/mango -c Resources/config.conf -p

# The mango source tree the port is compared with.
MANGO ?= $(HOME)/sources/mango

# Compare the mango names the port tracks (Tests/mango-keys, see script/mango-keys.sh)
# with another mango tree. New or removed names show as a diff; classify them in
# Sources/Port/macOS/MangoCompat.swift, then refresh with
#   script/mango-keys.sh $(MANGO) Tests/mango-keys
mango-diff:
	@tmp=$$(mktemp -d) && script/mango-keys.sh "$(MANGO)" "$$tmp" >/dev/null && \
	if diff -ru -x VERSION Tests/mango-keys "$$tmp"; then \
		echo "same names as Tests/mango-keys ($$(head -1 Tests/mango-keys/VERSION)) in $$(head -1 "$$tmp/VERSION")"; rm -rf "$$tmp"; \
	else rm -rf "$$tmp"; exit 1; fi

# Compare Resources/config.conf with mango's assets/config.conf: differing values, options
# commented out on macOS, the port's own lines, and mango entries missing or out of order.
config-diff:
	@swift script/config-diff.swift "$(MANGO)" Resources/config.conf

# Build Resources/config-mac.conf (the first start's macOS keys) from config.conf and
# mac-bindings.conf; FirstStartKeysTests fails until it is run after either changes.
mac-config:
	@swift script/mac-config.swift

# Regenerate the compatibility tables from the code: docs/compatibility.md (mango --list-ignored), README (mango --list-glance).
readme-tables: build
	$(BUILD_DIR)/mango --list-ignored > .build/mango-compat.md
	script/readme-tables.sh docs/compatibility.md .build/mango-compat.md
	$(BUILD_DIR)/mango --list-glance > .build/mango-glance.md
	script/readme-tables.sh README.md .build/mango-glance.md mango-glance

install: app
	@# Wait until it has really quit (it restores windows first), or `open` finds it still
	@# running and starts nothing.
	@# `chutney_restart` keeps hidden windows hidden for the new mango, which restores them
	@# from the saved layout. Only when the launch agent starts it again and the build
	@# keeps its Accessibility grant (a real signing identity); otherwise SIGTERM, which
	@# brings every window back into view first, as before.
	@if pgrep -xq mango; then echo "stopping running mango"; \
		if [ "$(CODESIGN_IDENTITY)" != "-" ] && launchctl print gui/$$(id -u)/$(LABEL) >/dev/null 2>&1; then \
			($(PREFIX)/bin/mmsg dispatch chutney_restart >/dev/null 2>&1 &); else pkill -x mango; fi; \
		for i in 1 2 3 4 5 6 7 8 9 10; do pgrep -xq mango || break; sleep 0.5; done; \
		if pgrep -xq mango; then pkill -x mango; \
			for i in 1 2 3 4 5 6 7 8 9 10; do pgrep -xq mango || break; sleep 0.5; done; fi; \
		if pgrep -xq mango; then echo "mango did not quit; stopping it hard"; pkill -9 -x mango; fi; fi
	@# The app from before the rename, and its launch agent (installed again below as $(LABEL)).
	@rm -f $(HOME)/.mango-old-agent
	@if launchctl print gui/$$(id -u)/$(OLD_LABEL) >/dev/null 2>&1; then touch $(HOME)/.mango-old-agent; \
		launchctl bootout gui/$$(id -u)/$(OLD_LABEL) 2>/dev/null; fi
	@rm -f $(HOME)/Library/LaunchAgents/$(OLD_LABEL).plist
	rm -rf "$(APP_DIR)/$(OLD_APP)"
	rm -rf "$(APP_DIR)/$(APP_NAME)"
	cp -R "$(APP)" "$(APP_DIR)/$(APP_NAME)"
	@# Register the new copy, or `open -a "Mango Chutney"` fails right after a reinstall.
	-@/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$(APP_DIR)/$(APP_NAME)"
	mkdir -p $(PREFIX)/bin
	ln -sf "$(APP_DIR)/$(APP_NAME)/Contents/MacOS/mmsg" $(PREFIX)/bin/mmsg
	ln -sf "$(APP_DIR)/$(APP_NAME)/Contents/MacOS/mango" $(PREFIX)/bin/mango
	@mkdir -p $(HOME)/.config/mango
	@test -f $(HOME)/.config/mango/config.conf || test -f $(HOME)/.config/mango/config.toml || \
		cp Resources/config.conf $(HOME)/.config/mango/config.conf
	@if launchctl print gui/$$(id -u)/$(LABEL) >/dev/null 2>&1 || test -f $(HOME)/.mango-old-agent; then \
		echo "reloading the $(LABEL) launch agent"; $(PREFIX)/bin/mmsg service install; fi
	@rm -f $(HOME)/.mango-old-agent
	@echo ""
	@echo "Installed $(APP_DIR)/$(APP_NAME) and $(PREFIX)/bin/{mango,mmsg}."
	@case ":$$PATH:" in *":$(PREFIX)/bin:"*) ;; *) echo "Note: $(PREFIX)/bin is not in your PATH.";; esac
	@echo "Config: ~/.config/mango/config.conf (or config.toml)"
	@echo "Start:  open -a \"Mango Chutney\"   (grant Accessibility on first start)"
	@echo "Login:  mmsg service install"

# A build for other Macs, as AeroSpace ships its own: signed with a fixed certificate
# (a self-made one is enough: Accessibility trusts the certificate, so the grant survives
# updates; ad-hoc signing would lose it on every update), not notarized. The cask removes
# the quarantine attribute after installing, so Gatekeeper does not stop the first start.
# Set CODESIGN_IDENTITY (local.mk), e.g. the name of a certificate made in Keychain Access ›
# Certificate Assistant › Create a Certificate (type Code Signing; choose "Let me override
# defaults" and a validity of 10+ years: the grant is tied to this certificate, and a new
# one costs every user the grant once). Keep a backup of it (export as .p12).
VERSION := $(shell /usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)
ZIP     := dist/MangoChutney-$(VERSION).zip

release:
	@test "$(CODESIGN_IDENTITY)" != "-" || { echo "error: set CODESIGN_IDENTITY to a certificate (ad-hoc builds lose the Accessibility grant on every update)"; exit 1; }
	$(MAKE) app
	codesign --verify --strict --verbose=2 "$(APP)"
	rm -f $(ZIP)
	@# No ._ files (extended attributes such as com.apple.provenance): unzip would add them
	@# to the bundle and break its signature.
	ditto -c -k --norsrc --noextattr --keepParent "$(APP)" $(ZIP)
	@shasum -a 256 $(ZIP)

# The Homebrew cask for the release zip (kim-raaschou/homebrew-tap: Casks/mangochutney.rb).
# The release is tagged v$(VERSION) on GitHub, with $(ZIP) attached.
cask:
	@test -f $(ZIP) || { echo "error: no $(ZIP); run make release first"; exit 1; }
	sed -e "s/@VERSION@/$(VERSION)/" -e "s/@SHA256@/$$(shasum -a 256 $(ZIP) | cut -d' ' -f1)/" \
		Resources/mangochutney.rb.in > dist/mangochutney.rb
	@echo "wrote dist/mangochutney.rb"

uninstall:
	-$(PREFIX)/bin/mmsg service uninstall 2>/dev/null
	-pkill -x mango
	rm -rf "$(APP_DIR)/$(APP_NAME)" "$(APP_DIR)/$(OLD_APP)"
	rm -f $(PREFIX)/bin/mmsg $(PREFIX)/bin/mango

run: build
	$(BUILD_DIR)/mango -d

clean:
	rm -rf .build dist
