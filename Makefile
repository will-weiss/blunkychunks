# Blunkychunks build.
#
#   make          compile every .tl into build/ as Lua 5.1
#   make run      compile, then launch the game in LOVE
#   make check    type-check all Teal sources (game + tests)
#   make test     run the rules-engine tests under the system Lua
#   make clean    remove build/
#
# Override LOVE if the binary lives somewhere else:
#   make run LOVE=/path/to/love

TL   ?= tl
LOVE ?= /Applications/love.app/Contents/MacOS/love
OUT  := build

SHARED := blunkychunks.tl board.tl
GAME   := $(wildcard src/*.tl)
TESTS  := $(wildcard tests/*.tl)

LUA := $(patsubst %.tl,$(OUT)/%.lua,$(SHARED)) \
       $(patsubst src/%.tl,$(OUT)/%.lua,$(GAME))

.PHONY: all game run check test clean

all: game

game: $(LUA)

$(OUT):
	mkdir -p $(OUT)

$(OUT)/%.lua: src/%.tl | $(OUT)
	$(TL) gen --gen-target=5.1 -c -o $@ $<

$(OUT)/%.lua: %.tl | $(OUT)
	$(TL) gen --gen-target=5.1 -c -o $@ $<

run: game
	$(LOVE) $(OUT) $(ARGS)

check:
	$(TL) check $(SHARED) $(GAME) $(TESTS)

test:
	$(TL) run tests/run.tl

clean:
	rm -rf $(OUT)
