--- LOVE configuration. Compiled to build/conf.lua alongside main.lua.
--- With --server the game runs headless: no window, no graphics or sound,
--- just the network server (see main.tl).

function love.conf(t: love.Conf)
   t.identity = "blunkychunks"
   t.version = "11.4"
   for _, a in ipairs(arg or {}) do
      if a == "--server" then
         t.window = nil
         t.modules.window, t.modules.graphics, t.modules.audio, t.modules.sound = false, false, false, false
         t.modules.joystick, t.modules.video, t.modules.image = false, false, false
         return
      end
   end
   t.window.title = "Blunkychunks"
   t.window.width = 1440
   t.window.height = 900
   t.window.vsync = 1
   t.window.resizable = false
   t.window.highdpi = true
end
