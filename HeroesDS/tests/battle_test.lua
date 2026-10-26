-- Tests of a whole battle (HeroesDS/combat/battle.lua), run by test_combat.py through lupa.
-- Argument: the HeroesDS folder.

local root = ...
package.path = root .. "/?.lua;" .. package.path

local grid = require("combat.grid")
local stats = require("combat.stats")
local battle = require("combat.battle")

local T = {}

local function eq(got, want, what)
  if got ~= want then
    error(string.format("%s: got %s, want %s", what or "value", tostring(got), tostring(want)), 2)
  end
end

-- A creature stack; morale 0 (army morale +1, bonus -1) so no morale rolls change the order
local function cr(over, count)
  local def = { name = "test", hp = 10, dmg = { 2, 4 }, attack = 10, defense = 10, move = 10,
                speed = 5, shots = 0, size = 2, level = 1, alignment = "might", abilities = {} }
  for k, v in pairs(over or {}) do def[k] = v end
  local st = stats.creature("test", def, count or 10)
  st.morale_bonus = -1
  return st
end

local function make(att, def, seed, field)
  return battle.new({ seed = seed or 1, field = field,
                      sides = { [0] = { stacks = att }, [1] = { stacks = def } } })
end

local function find(events, kind)
  local out = {}
  for _, e in ipairs(events) do if e.t == kind then out[#out + 1] = e end end
  return out
end

local function place(u, x, y) u.x, u.y = x, y end

---------------------------------------------------------------------------------------------
function T.deploy()
  local a1, a2 = cr(), cr({ size = 5 })
  local d1 = cr()
  local b = make({ a1, a2 }, { d1 })
  eq(a1.id, 1); eq(a2.id, 2); eq(d1.id, 3)
  eq(a1.x, 76); eq(a1.y, 51, "slot 0, size 2: (2-1)//2 = 0 back")
  eq(a2.x, 85 - 2); eq(a2.y, 55 - 2, "slot 1, size 5: 2 back")
  eq(d1.x, 33); eq(d1.y, 32)
  eq(a1.facing, "ne"); eq(d1.facing, "sw")
  eq(b.round, 1)
  local ev = b:take_events()
  eq(ev[1].t, "round"); eq(ev[#ev].t, "turn")
  -- a slot taken by an obstacle: the nearest free place
  local f = grid.new_field()
  f:add_obstacle("rock", 76, 51, 1, 1, true)
  local x = cr()
  make({ x }, { cr() }, 1, f)
  assert(not (x.x <= 76 and x.x + 1 >= 76 and x.y <= 51 and x.y + 1 >= 51), "kept off the rock")
end

function T.army_morale()
  local chaos, life = cr({ alignment = "chaos" }), cr({ alignment = "life" })
  eq(battle.army_morale("chaos", { chaos }), 1)
  eq(battle.army_morale("chaos", { chaos, life }), -4, "opposed: -5")
  local order = cr({ alignment = "order" })
  eq(battle.army_morale("chaos", { chaos, order }), -4, "order and chaos are opposed")
  local death = cr({ alignment = "death" })
  eq(battle.army_morale("chaos", { chaos, death }), 0, "neighbours: -1")
  local might = cr({ alignment = "might" })
  eq(battle.army_morale("chaos", { chaos, might }), -1, "might: -2")
  local skel = cr({ alignment = "death", abilities = { undead = true } })
  eq(battle.army_morale("chaos", { chaos, skel }), -2, "neighbour -1, undead -2")
  eq(battle.army_morale("death", { skel }), 1, "death does not mind undead")
end

function T.turn_order_and_wait()
  local fast, slow = cr({ speed = 9 }), cr({ speed = 3 })
  local e1, e2 = cr({ speed = 9 }), cr({ speed = 6 })
  local b = make({ fast, slow }, { e1, e2 })
  eq(b:current().id, fast.id, "ties: the attacker first")
  local q = b:queue()
  eq(q[1], fast.id); eq(q[2], e1.id); eq(q[3], e2.id); eq(q[4], slow.id)
  assert(b:act({ type = "wait" }))
  eq(b:current().id, e1.id)
  assert(b:act({ type = "wait" }))
  q = b:queue()
  eq(q[1], e2.id); eq(q[2], slow.id)
  eq(q[3], fast.id, "waiting, the same key: side 0 first"); eq(q[4], e1.id)
  b:act({ type = "defend" }); b:act({ type = "defend" })
  eq(b:current().id, fast.id, "the waiting attacker before the waiting defender (same key)")
  local ok, err = b:act({ type = "wait" })
  eq(ok, nil, "once a round"); eq(err, "cannot wait")
end

function T.defend_lasts_until_own_turn()
  local a, d = cr({ speed = 9 }), cr({ speed = 3 })
  local b = make({ a }, { d })
  b:act({ type = "defend" })
  eq(a.defending, true)
  b:act({ type = "defend" })              -- d; round 2 starts with a
  eq(b.round, 2); eq(b:current().id, a.id)
  eq(a.defending, false, "cleared when its turn comes")
  eq(d.defending, true)
end

function T.move_and_step_toward()
  local a, d = cr({ speed = 9, move = 6 }), cr()
  local b = make({ a }, { d })
  local o = b:options()
  eq(o.stack, a.id)
  assert(o.move[grid.key(a.x - 6, a.y)] ~= nil, "6 cells")
  local ev = assert(b:act({ type = "move", x = 70, y = 51 }))
  eq(find(ev, "move")[1].path[6][1], 70)
  eq(a.x, 70); eq(a.moved, 6.0)
  b:act({ type = "defend" })              -- d
  -- far beyond this turn: as far as it goes along the way
  ev = assert(b:act({ type = "move", x = 40, y = 51 }))
  eq(a.x, 64, "6 more cells toward it")
end

-- Two stacks side by side, ready to fight
local function duel(over_a, over_d, na, nd, seed)
  local a, d = cr(over_a, na), cr(over_d, nd)
  local b = make({ a }, { d }, seed)
  place(a, 50, 52); place(d, 50, 50)     -- d touches a (y 50..51 vs 52)
  return b, a, d
end

function T.melee_and_retaliation()
  local b, a, d = duel({ speed = 9 }, { speed = 3 }, 10, 10)
  local o = b:options()
  eq(o.melee[d.id], grid.key(50, 52), "strikes from where it stands")
  local ev = assert(b:act({ type = "melee", target = d.id }))
  local blows = find(ev, "melee")
  eq(#blows, 2); eq(blows[1].stack, a.id); eq(blows[2].stack, d.id, "struck back")
  eq(#find(ev, "together"), 1, "at once")
  assert(d.count < 10 and a.count < 10)
  eq(d.retaliated, true)
  -- a second attack on d this round: no strike back
  b:act({ type = "defend" })              -- d
  eq(b.round, 2)
  d.retaliated = true                      -- as if it had already struck back this round
  ev = assert(b:act({ type = "melee", target = d.id }))
  eq(#find(ev, "melee"), 1, "once a round")
end

function T.simultaneous_exchange_with_the_dead()
  -- 50 strong attackers kill a lone target in one blow
  battle.dead_strike_back = true
  local b, a, d = duel({ speed = 9, dmg = { 10, 10 } }, { speed = 3, dmg = { 5, 5 } }, 50, 1)
  local ev = assert(b:act({ type = "melee", target = d.id }))
  local blows = find(ev, "melee")
  eq(d.count, 0)
  eq(blows[2].stack, d.id)
  assert(blows[2].damage > 0, "it strikes back with the stack it had")
  eq(ev[#ev].t, "over")
  eq(b.winner, 0)
  eq(find(ev, "die")[1].stack, d.id)
  battle.dead_strike_back = false
  b, a, d = duel({ speed = 9, dmg = { 10, 10 } }, { speed = 3, dmg = { 5, 5 } }, 50, 1)
  ev = assert(b:act({ type = "melee", target = d.id }))
  eq(find(ev, "melee")[2].damage, 0, "the blow lands first (H9, the default)")
  local ok, err = b:act({ type = "defend" })
  eq(ok, nil); eq(err, "the battle is over")
end

function T.first_strike()
  local b, a, d = duel({ speed = 9, abilities = { first_strike = true }, dmg = { 10, 10 } },
                       { speed = 3 }, 20, 30)
  local ev = assert(b:act({ type = "melee", target = d.id }))
  eq(#find(ev, "together"), 0, "not at once")
  local blows = find(ev, "melee")
  eq(blows[1].stack, a.id); eq(blows[2].stack, d.id)
  -- d answered with what was left: 30 - killed
  eq(blows[2].left, a.count)
end

function T.strikes_twice_and_no_retaliation()
  local b, a, d = duel({ speed = 9, abilities = { strikes_twice = true, no_retaliation = true } },
                       { speed = 3 }, 10, 100)
  local ev = assert(b:act({ type = "melee", target = d.id }))
  local blows = find(ev, "melee")
  eq(#blows, 2); eq(blows[1].stack, a.id); eq(blows[2].stack, a.id)
end

function T.attack_from_a_chosen_side()
  local a, d = cr({ speed = 9, move = 8 }), cr()
  local b = make({ a }, { d })
  place(a, 50, 56); place(d, 50, 50)      -- 4 cells between them
  local pos = b:attack_positions(a, d)
  assert(pos[grid.key(50, 52)] ~= nil and pos[grid.key(48, 52)] ~= nil)
  eq(pos[grid.key(50, 56)], nil, "not from where it stands")
  local ok, err = b:act({ type = "melee", target = d.id, x = 50, y = 60 })
  eq(ok, nil); eq(err, "cannot strike from there")
  local ev = assert(b:act({ type = "melee", target = d.id, x = 48, y = 52 }))
  eq(a.x, 48); eq(a.y, 52)
  eq(find(ev, "move")[1].stack, a.id)
  -- out of reach this turn: walks toward it
  local f, g = cr({ speed = 9, move = 6 }), cr()   -- about 52 cells away: 9 turns
  b = make({ f }, { g })
  ev = assert(b:act({ type = "melee", target = g.id }))
  eq(#find(ev, "melee"), 0); eq(#find(ev, "move"), 1)
end

function T.charge_counts_cells_walked()
  local a, d = cr({ speed = 9, move = 20, abilities = { charging = true }, dmg = { 10, 10 } }), cr({ defense = 10 })
  local b = make({ a }, { d })
  place(a, 50, 62); place(d, 50, 50)      -- 10 cells to walk
  local p = b:preview({ type = "melee", target = d.id, x = 50, y = 52 })
  eq(p.min, 113); eq(p.max, 113, "10 x 10 x 1.13")
end

function T.shooting()
  local a = cr({ speed = 9, shots = 5, abilities = { ranged = true } }, 10)
  local d = cr({ speed = 3, shots = 5, abilities = { ranged = true } }, 10)
  local b = make({ a }, { d })
  local o = b:options()
  eq(o.shoot[d.id], 2, "over 40 cells")
  local ev = assert(b:act({ type = "shoot", target = d.id }))
  local shots = find(ev, "shoot")
  eq(#shots, 2); eq(shots[2].stack, d.id, "shoots back")
  eq(a.shots, 4); eq(d.shots, 4)
  -- an enemy next to it: no shooting
  b:act({ type = "defend" })
  place(d, a.x - 2, a.y)
  b.version = b.version + 1
  o = b:options()
  eq(o.shoot[d.id], nil)
  local ok, err = b:act({ type = "shoot", target = d.id })
  eq(ok, nil); eq(err, "cannot shoot")
end

function T.lost_turn()
  local a, d = cr({ speed = 9 }), cr({ speed = 3 })
  a.effects.stun = { turns = 1 }
  local b = make({ a }, { d })
  eq(b:current().id, d.id, "the stunned stack lost its turn")
  local ev = b:take_events()
  eq(find(ev, "effect")[1].effect, "stun")
  eq(a.effects.stun, nil, "counted down")
  b:act({ type = "defend" })
  eq(b:current().id, a.id, "next round it acts")
end

-- A simple driver: shoot the lowest id it can, else strike, else walk at it, else defend
local function auto(b)
  local o = b:options()
  local best
  for id in pairs(o.shoot) do if not best or id < best then best = id end end
  if best then return b:act({ type = "shoot", target = best }) end
  for id, pos in pairs(o.melee) do if pos and (not best or id < best) then best = id end end
  if best then return b:act({ type = "melee", target = best }) end
  for id in pairs(o.melee) do if not best or id < best then best = id end end
  if best then
    local ev = b:act({ type = "melee", target = best })
    if ev then return ev end
  end
  return b:act({ type = "defend" })
end

local function fight(seed)
  local att = { cr({ speed = 7, move = 14 }, 20), cr({ speed = 5, shots = 8, abilities = { ranged = true } }, 12) }
  local def = { cr({ speed = 6, move = 12, size = 3, hp = 25, dmg = { 3, 6 } }, 9), cr({ speed = 8, move = 20 }, 15) }
  att[1].luck = 2; def[2].luck = -2
  local b = make(att, def, seed)
  local n = 0
  while not b.finished and n < 1000 do
    assert(auto(b), "a command failed")
    n = n + 1
  end
  return b, n
end

function T.replay_is_deterministic()
  local b1, n1 = fight(1234)
  local b2, n2 = fight(1234)
  assert(b1.finished, "the battle ends")
  eq(n1, n2, "same number of actions")
  eq(b1:checksum(), b2:checksum(), "same state")
  local b3 = fight(99)
  assert(b3:checksum() ~= b1:checksum(), "another seed, another battle")
end

function T.round_limit()
  local a, d = cr({ speed = 9 }), cr()
  local b = make({ a }, { d })
  local n = 0
  while not b.finished and n < 1000 do b:act({ type = "defend" }); n = n + 1 end
  eq(b.round, battle.MAX_ROUNDS + 1)
  eq(b.winner, 0)
end

---------------------------------------------------------------------------------------------
local names = {}
for name in pairs(T) do names[#names + 1] = name end
table.sort(names)
local failed = {}
for _, name in ipairs(names) do
  local ok, err = pcall(T[name])
  if not ok then failed[#failed + 1] = name .. ": " .. tostring(err) end
end
if #failed > 0 then error(#failed .. " failed:\n" .. table.concat(failed, "\n"), 0) end
return #names
