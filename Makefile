# Blunkychunks build.
#
#   make          compile every .tl into build/ as Lua 5.1
#   make run      compile, then launch the game in LOVE (you are Player 1)
#   make bots     compile, then launch an all-bot match
#   make check    type-check all Teal sources (game, tests and scripts)
#   make test     run the rules-engine tests under the system Lua
#   make soak     play whole bot matches headless, checking invariants
#   make images   redraw the README's figures
#   make dist     package the standalone game for every platform into dist/
#                 (make love / mac / windows / linux for just one)
#   make clean    remove build/ and dist/
#
# The board is the notched hexagon; pick its size with DIAMETER (the central
# hexagon's width in triangles, even) and NOTCH, for run, bots, soak and images:
#   make run DIAMETER=12 NOTCH=5
# Anything else goes in ARGS, e.g. make run ARGS="--seed 42 --fast".
# Override LOVE if the binary lives somewhere else:
#   make run LOVE=/path/to/love
#
# Packaging downloads the official LOVE $(LOVE_VERSION) runtimes once into
# .love-runtimes/ and needs only curl, zip and unzip, so every platform can be
# built from a Mac (the Mac app is ad-hoc signed when codesign is around):
#   dist/blunkychunks.love           any OS with LOVE installed
#   dist/blunkychunks-macos.zip      Blunkychunks.app
#   dist/blunkychunks-win64.zip      blunkychunks.exe plus LOVE's DLLs
#   dist/blunkychunks-linux.tar.gz   LOVE's x86_64 AppImage, the .love and a
#                                    ./blunkychunks launcher

TL       ?= tl
LOVE     ?= /Applications/love.app/Contents/MacOS/love
OUT      := build
DIAMETER ?= 22
NOTCH    ?= 8
BOARD    := --diameter $(DIAMETER) --notch $(NOTCH)

SHARED := blunkychunks.tl board.tl
GAME   := $(wildcard src/*.tl)
TESTS  := $(wildcard tests/*.tl)

LUA := $(patsubst %.tl,$(OUT)/%.lua,$(SHARED)) \
       $(patsubst src/%.tl,$(OUT)/%.lua,$(GAME))

.PHONY: all game run bots check test soak images clean distclean \
        dist love mac windows linux

all: game

game: $(LUA)

$(OUT):
	mkdir -p $(OUT)

$(OUT)/%.lua: src/%.tl | $(OUT)
	$(TL) gen --gen-target=5.1 -c -o $@ $<

$(OUT)/%.lua: %.tl | $(OUT)
	$(TL) gen --gen-target=5.1 -c -o $@ $<

run: game
	$(LOVE) $(OUT) $(BOARD) $(ARGS)

bots: game
	$(LOVE) $(OUT) --bots $(BOARD) $(ARGS)

check:
	$(TL) check $(SHARED) $(GAME) $(TESTS) render.tl layouts.tl

test:
	$(TL) run tests/run.tl

soak:
	$(TL) run tests/soak.tl -- $(BOARD) $(ARGS)

images:
	$(TL) run render.tl -- $(BOARD) $(ARGS)

clean:
	rm -rf $(OUT) $(DIST)

distclean: clean
	rm -rf $(RUNTIMES)

# --- Packaging ---------------------------------------------------------------

NAME         := blunkychunks
APP          := Blunkychunks
BUNDLE_ID    ?= com.bringitpop.blunkychunks
LOVE_VERSION ?= 11.4
LOVE_URL     := https://github.com/love2d/love/releases/download/$(LOVE_VERSION)
DIST         := dist
RUNTIMES     := .love-runtimes
STAGE        := $(DIST)/stage

LOVE_FILE := $(DIST)/$(NAME).love
MAC_ZIP   := $(DIST)/$(NAME)-macos.zip
WIN_ZIP   := $(DIST)/$(NAME)-win64.zip
LINUX_TAR := $(DIST)/$(NAME)-linux.tar.gz

MAC_RT   := $(RUNTIMES)/love-$(LOVE_VERSION)-macos.zip
WIN_RT   := $(RUNTIMES)/love-$(LOVE_VERSION)-win64.zip
LINUX_RT := $(RUNTIMES)/love-$(LOVE_VERSION)-x86_64.AppImage

dist: love mac windows linux
love: $(LOVE_FILE)
mac: $(MAC_ZIP)
windows: $(WIN_ZIP)
linux: $(LINUX_TAR)

# dist is also a target name, so recipes make their own directories.
$(RUNTIMES)/%:
	mkdir -p $(RUNTIMES)
	curl -fL --retry 3 -o $@.part $(LOVE_URL)/$*
	mv $@.part $@

# The .love is just the compiled Lua zipped with main.lua at its root.
$(LOVE_FILE): $(LUA)
	mkdir -p $(DIST)
	rm -f $@
	cd $(OUT) && zip -9 -q -X $(abspath $@) $(notdir $(LUA))

# Windows: love.exe with the .love appended is a fused game; it needs LOVE's
# DLLs next to it.
$(WIN_ZIP): $(LOVE_FILE) $(WIN_RT)
	rm -rf $(STAGE)/win $@
	mkdir -p $(STAGE)/win
	unzip -q $(WIN_RT) -d $(STAGE)/win
	mv $(STAGE)/win/love-*-win64 $(STAGE)/win/$(NAME)
	cd $(STAGE)/win/$(NAME) && rm -f lovec.exe changes.txt readme.txt game.ico love.ico
	cat $(STAGE)/win/$(NAME)/love.exe $(LOVE_FILE) > $(STAGE)/win/$(NAME)/$(NAME).exe
	rm $(STAGE)/win/$(NAME)/love.exe
	cd $(STAGE)/win && zip -9 -q -r $(abspath $@) $(NAME)

# macOS: love.app renamed, with the .love inside Contents/Resources.
$(MAC_ZIP): $(LOVE_FILE) $(MAC_RT)
	rm -rf $(STAGE)/mac $@
	mkdir -p $(STAGE)/mac
	unzip -q $(MAC_RT) -d $(STAGE)/mac
	mv $(STAGE)/mac/love.app $(STAGE)/mac/$(APP).app
	cp $(LOVE_FILE) $(STAGE)/mac/$(APP).app/Contents/Resources/$(NAME).love
	plutil -replace CFBundleIdentifier -string $(BUNDLE_ID) $(STAGE)/mac/$(APP).app/Contents/Info.plist
	plutil -replace CFBundleName -string $(APP) $(STAGE)/mac/$(APP).app/Contents/Info.plist
	plutil -remove UTExportedTypeDeclarations $(STAGE)/mac/$(APP).app/Contents/Info.plist
	plutil -remove CFBundleDocumentTypes $(STAGE)/mac/$(APP).app/Contents/Info.plist
	if command -v codesign >/dev/null; then codesign --force --deep -s - $(STAGE)/mac/$(APP).app; fi
	cd $(STAGE)/mac && zip -9 -q -r -y $(abspath $@) $(APP).app

# Linux: an AppImage can't be fused without Linux-only tools, so ship LOVE's
# AppImage beside the .love with a launcher script.
$(LINUX_TAR): $(LOVE_FILE) $(LINUX_RT)
	rm -rf $(STAGE)/linux $@
	mkdir -p $(STAGE)/linux/$(NAME)
	cp $(LINUX_RT) $(STAGE)/linux/$(NAME)/love.AppImage
	cp $(LOVE_FILE) $(STAGE)/linux/$(NAME)/
	printf '#!/bin/sh\nhere="$$(dirname "$$(readlink -f "$$0")")"\nexec "$$here/love.AppImage" "$$here/$(NAME).love" "$$@"\n' > $(STAGE)/linux/$(NAME)/$(NAME)
	chmod +x $(STAGE)/linux/$(NAME)/$(NAME) $(STAGE)/linux/$(NAME)/love.AppImage
	tar -C $(STAGE)/linux -czf $@ $(NAME)
