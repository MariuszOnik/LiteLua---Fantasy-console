-- LiteLua API documentation: middleclass (built-in library, MIT license,
-- https://github.com/kikito/middleclass). Format: see docs/api/README.md.
return {
  module = "middleclass",
  title = "Classes (middleclass)",
  summary = "Classes for object oriented code: local class = "
         .. "require(\"middleclass\"). Built in (nitro:/lib, middleclass 4.1.1 by "
         .. "Enrique Garcia Cota, MIT license). Method calls make no garbage; "
         .. "an object costs as much as a plain table with a metatable (D54).",
  since = "P10c",
  entries = {
    {
      name = "class", kind = "function",
      sig = "class(name, [super]) -> Class",
      args = {
        { "name", "string", "name of the class (for tostring)" },
        { "super", "Class", "a class to inherit from" },
      },
      ret = { { "Class", "the new class" } },
      desc = "Makes a class. Methods are functions on the class; initialize is "
          .. "the constructor. Call the class (or Class:new) to make an object.",
      example = [[
local class = require("middleclass")
local Enemy = class("Enemy")
function Enemy:initialize(x, y)
  self.x, self.y, self.hp = x, y, 3
end
function Enemy:update() self.x = self.x - 1 end
local e = Enemy(100, 50)  -- or Enemy:new(100, 50)
e:update()]],
    },
    {
      name = "Class:subclass", kind = "function",
      sig = "Class:subclass(name) -> Class",
      args = { { "name", "string", "name of the subclass" } },
      desc = "Makes a class that inherits all methods (also initialize). To "
          .. "call the parent's version: Parent.method(self, ...).",
      example = [[
local Boss = Enemy:subclass("Boss")
function Boss:initialize(x, y)
  Enemy.initialize(self, x, y)
  self.hp = 20
end]],
    },
    {
      name = "Class:new", kind = "function",
      sig = "Class:new(...) -> object",
      desc = "Makes an object and calls initialize(...). Class(...) does the "
          .. "same. Making objects every frame makes garbage: for bullets and "
          .. "particles keep a pool and reuse them.",
      example = [[
-- A pool: objects are made once and reused
local pool = {}
for i = 1, 50 do pool[i] = Bullet(0, 0); pool[i].alive = false end
local function fire(x, y)
  for _, b in ipairs(pool) do
    if not b.alive then b:reset(x, y); return b end
  end
end]],
    },
    {
      name = "Class.static", kind = "table",
      sig = "Class.static.name = value",
      desc = "Class methods and values (not of the objects): "
          .. "function Class.static:make() ... end, called as Class:make(). "
          .. "Subclasses inherit them. Class.static:allocate() can be "
          .. "replaced to make the object table with room for its fields.",
      example = [[
function Enemy.static:spawn_row(n)
  local t = {}
  for i = 1, n do t[i] = self(i * 20, 0) end
  return t
end
local row = Enemy:spawn_row(5)]],
    },
    {
      name = "Class:include", kind = "function",
      sig = "Class:include(mixin, ...) -> Class",
      args = { { "mixin", "table", "functions to copy into the class" } },
      desc = "Copies the functions of a table (a mixin) into the class: shared "
          .. "behavior without inheritance. mixin.included(mixin, Class) is "
          .. "called if present.",
      example = [[
local HasHealth = {
  hit = function(self, n) self.hp = self.hp - n end,
}
Enemy:include(HasHealth)]],
    },
    {
      name = "obj:isInstanceOf", kind = "function",
      sig = "obj:isInstanceOf(Class) -> boolean",
      desc = "True if obj is an object of Class or of a subclass. Also "
          .. "Class:isSubclassOf(Other). obj.class is the object's class.",
      example = [[
if e:isInstanceOf(Boss) then music("boss") end]],
    },
    {
      name = "__tostring", kind = "field",
      sig = "function Class:__tostring() ... end",
      desc = "Metamethods (__tostring, __eq, __lt, __add, __len, __call...) "
          .. "are written as methods and are inherited.",
      example = [[
local Vec = class("Vec")
function Vec:initialize(x, y) self.x, self.y = x, y end
function Vec:__add(o) return Vec(self.x + o.x, self.y + o.y) end
function Vec:__tostring() return self.x .. "," .. self.y end]],
    },
  },
}
