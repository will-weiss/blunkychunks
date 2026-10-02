# Blunkychunks build.
#
#   make          compile every .tl into build/ as Lua 5.1
#   make run      compile, then launch the game in LOVE (you are Player 1)
#   make bots     compile, then launch an all-bot match
#   make check    type-check all Teal sources (game, tests and scripts)
#   make test     run the rules-engine tests under the system Lua
#   make soak     play whole bot matches headless, checking invariants
#   make images   redraw the README's figures
#   make clean    remove build/
#
# The board is the notched hexagon; pick its size with DIAMETER (the central
# hexagon's width in triangles, even) and NOTCH, for run, bots, soak and images:
#   make run DIAMETER=12 NOTCH=5
# Anything else goes in ARGS, e.g. make run ARGS="--seed 42 --fast".
# Override LOVE if the binary lives somewhere else:
#   make run LOVE=/path/to/love

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

.PHONY: all game run bots check test soak images clean

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
	rm -rf $(OUT)
