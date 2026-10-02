--- LOVE configuration. Compiled to build/conf.lua alongside main.lua.

function love.conf(t: love.Conf)
   t.identity = "blunkychunks"
   t.version = "11.4"
   t.window.title = "Blunkychunks"
   t.window.width = 1440
   t.window.height = 900
   t.window.vsync = 1
   t.window.resizable = false
   t.window.highdpi = true
end
