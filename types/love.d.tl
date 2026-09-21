--- The slice of the LOVE 11.4 API this game uses, declared so `tl check` can
--- type the callbacks and drawing calls. Extend as the game grows.

global record love
   record Font
      userdata
      getHeight: function(Font): number
      getWidth: function(Font, string): number
   end

   record graphics
      setBackgroundColor: function(number, number, number, ?number)
      setColor: function(number, number, number, ?number)
      setLineWidth: function(number)
      setLineJoin: function(string)
      polygon: function(string, ...: number)
      line: function(...: number)
      rectangle: function(string, number, number, number, number, ?number, ?number)
      circle: function(string, number, number, number)
      print: function(string, number, number, ?number, ?number, ?number)
      printf: function(string, number, number, number, ?string, ?number, ?number, ?number)
      newFont: function(number): Font
      setFont: function(Font)
      getWidth: function(): number
      getHeight: function(): number
      push: function()
      pop: function()
      translate: function(number, number)
      captureScreenshot: function(string)
   end

   record event
      quit: function(?integer)
   end

   record ConfWindow
      title: string
      width: integer
      height: integer
      vsync: integer
      resizable: boolean
      highdpi: boolean
   end

   record Conf
      identity: string
      version: string
      window: ConfWindow
   end

   conf: function(Conf)
   load: function({string})
   update: function(number)
   draw: function()
   keypressed: function(string)
end
