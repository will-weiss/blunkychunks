-- Teal project config. `tl check`, `tl run` and `tl gen` all read this.
--
-- Game modules live in src/ and share blunkychunks.tl / board.tl at the root.
-- LOVE 11.4 runs LuaJIT, so everything is generated as Lua 5.1.
return {
   include_dir = { ".", "src", "types" },
   global_env_def = "love",
   gen_target = "5.1",
}
