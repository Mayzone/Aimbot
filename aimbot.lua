local draw_targets = true								-- Outlines targets with arrow and box
local freeze_accuracy = false							-- When aimbot is active, freezes the accuracy until, aimbot is off.
local target_priority = 1								-- Set to 1 to target closest, 2 for furthest and 3 for random
local always_headshot = true							-- Or a random bodypart
local auto_replenish_ammo = false						-- Replenish ammo when emety by cheating ammo, requires auto_reload true.
local auto_reload = true								-- Set to true to reload weapon when emety.
local shoot_through_wall = false						-- Set to true if you want to target enemies through walls
local shoot_through_shield = true						-- Set to true to shoot through shields when using special ammo or not shoot shields.
local silent_shooting = false
local fov = 100											-- 1-180. 135 recommended for whole screen as the fov is a cone from your camera and this is the cone width
local max_distance = 1500								-- max distance, 0 for weapon range if possible or it's gona be 7000m

local fire_delay = 0.07									-- Adds fire delay on top of weapons fire delay
local custom_damage_by_unit = false						-- Set to true to use defined damage by unit in table bellow or false, this has priority 1.
local custom_damage = false								-- Custom damage in number format or false. Prioritizing custom_damage_by_unit first.

local shoot_civilians = false							-- Set to true to shoot civilians.
local shoot_turrets = true								-- Set to true to shoot turrets, shoot_through_wall is requires.
local shoot_enemies = true								-- Set to true to shoot enemies.

local shoot_when_moving = true							-- set to true to auto shoot when moving. 
local shoot_when_aiming = false							-- set to true to auto shoot when aiming down sight.
local shoot_when_running = true						-- set to true to auto shoot when running.
local shoot_when_crouching = true						-- set to true to auto shoot when crouching.
local shoot_when_keybind_is_pressed = ""				-- set "left shift", "right shift", "left ctrl", "right ctrl", "left alt", "t", "g", "4" for mouse 4/number 4 and "mouse wheel up" e.g to auto shoot.
local state_blacklist = {								-- Set to true to shoot in those states
	["standard"] 							= true,		-- masked
	["bleed_out"] 							= true,		-- on ground and able to shoot
	["bipod"] 								= true,		-- using lmg extension
	["driving"] 							= false,	-- driving
	["fatal"] 								= false,	-- on ground not able to shoot
	["jerry2"]								= false,	-- parachute
	["mask_off"]							= false,	-- mask off
	["tased"] 								= true,		-- when tased
	["incapacitated"] 						= false,	-- on ground not able to shoot
	["carry"] 								= true,		-- carrying bags
	["arrested"] 							= false,	-- cuffed
	["civilian"] 							= false,	-- mask off and can interact (start of golden grin casino heist)
	["clean"] 								= false		-- mask off and can't interact (start of panic room heist)
}
local custom_damage_table = {
	["phalanx_minion"]						= 1000, 	-- Wintergoons
	["tank"]								= false
}
local fire_delay_by_unit = {
	["tank"]								= 0,
	["tank_mini"]							= 0,		-- Minigundozer
	["tank_medic"]							= 0,		-- Medic Dozer
	["tank_hw"]								= 0,		-- Headless Titandozers
	["sentry_gun"]							= 0			-- enemy sentry
}
local blocked_units = {									-- Set to true to block shooting those units
	["triad_boss"]							= true,		-- mountain master triad boss
	["triad_boss_no_armor"]					= true,		-- mountain master triad boss with no armor
	["phalanx_vip"]							= true		-- captain winter
}
---------------------------------------------------------------------------------------------------------
local mod_name = "Mayzones_Aimbot"
local loaded = rawget(_G, mod_name)
local c = not loaded and rawset(_G, mod_name, {}) and _G[mod_name] or loaded

c.active = not c.active
managers.mission._fading_debug_output:script().log(string.format("%s", (c.active and "Aimbot - Activated" or "Aimbot - Deactivated")), (c.active and Color.green or Color.red))

if not loaded then
	math.randomseed(os.time())
	local player_sentries = {["@IDc71d763cd8d33588@"] = true, ["@IDb1f544e379409e6c@"] = true}
	local special_weapons = {"flamethrower","bow"}
	local body_map = {
		"Hips","Spine","Spine1","Spine2","Neck","Head",
		"LeftShoulder","LeftArm","LeftForeArm","RightShoulder","RightArm","RightForeArm",
		"LeftUpLeg","LeftLeg","LeftFoot","RightUpLeg","RightLeg","RightFoot"
	}
	local controlls = {
		primary_attack = true, throw_grenade = true, reload = true,
		switch_weapon = true, switch_weapon = true, jump = true,
		interact = true, use_item = true, melee = true,
		duck = not shoot_when_crouching, run = not shoot_when_running, secondary_attack = not shoot_when_aiming
	}

	local function get_fire_delay(wep_base)
		local fire_rate_data = wep_base:recoil_wait() or wep_base:fire_mode() == "single" and 0.6 or fire_delay
		local unit_fire_rate = fire_delay_by_unit[c.unit_base._tweak_table] or c.unit_base.sentry_gun and fire_delay_by_unit["sentry_gun"]
		local min_rate = (unit_fire_rate or fire_delay) + fire_rate_data
		local max_rate = (unit_fire_rate or fire_delay) + fire_rate_data / 3
		return math.random()*(max_rate-min_rate) + min_rate, min_rate, max_rate
	end

	local function key_pressed()
		local controller = c.player_unit and c.player_unit:base() and c.player_unit:base():controller() or {}
		local active_menu = managers.menu._open_menus[#managers.menu._open_menus]

		if not state_blacklist[managers.player._current_state]
		or managers.hud and managers.hud._chat_focus == true
		or active_menu and active_menu.name == "menu_pause"
		or managers.network.account and managers.network.account._overlay_opened
		or #shoot_when_keybind_is_pressed > 0 and not (Input:keyboard():down(Idstring(shoot_when_keybind_is_pressed)) or Input:mouse():down(Idstring(shoot_when_keybind_is_pressed)))
		or controller and mvector3.length(controller:get_input_axis("move")) > PlayerStandard.MOVEMENT_DEADZONE and not shoot_when_moving then
			return true
		end

		for k, v in pairs(controlls) do
			if v and (controller:get_input_pressed(k) or controller:get_input_bool(k)) then
				return true
			end
		end
	end

	local function hit_damage(base, dmg)
		return custom_damage_by_unit and custom_damage_table[base._tweak_table] and custom_damage_table[base._tweak_table] / 100 or custom_damage and custom_damage / 100 or dmg
	end

	local function is_sentry_gun_active(unit)
		local movement = unit:movement()
		local turret_states = {active = true, rearming = true, activating = true}
		return type(movement) == "table" and turret_states[movement._state] ~= nil
	end

	local function is_hostage(unit)
		local brain = alive(unit) and unit.brain and unit:brain()
		local char_dmg = brain and unit:character_damage()
		local anim = unit:anim_data() -- for hostage trade
		if blocked_units[unit:base()._tweak_table] or player_sentries[unit:name():t()] or char_dmg and (char_dmg._dead or char_dmg._invulnerable or char_dmg._immortal or char_dmg._god_mode) or brain.is_hostage and brain:is_hostage() or not brain:is_hostile() or anim and (anim.hands_tied or anim.tied) then
			return true
		end
	end

	local function get_mask()
		local masks = {}
		masks[#masks + 1] = shoot_enemies and "enemies" or nil
		masks[#masks + 1] = shoot_civilians and "civilians" or nil
		masks[#masks + 1] = shoot_turrets and "sentry_gun" or nil
		return managers.slot:get_mask(unpack(masks))
	end

	local function get_target(player_unit, wep_base, tweak, special_wep)
		local count = {}
		local camera = player_unit:camera()
		local camera_position = camera:position()

		if shoot_through_wall then
			wep_base._bullet_slotmask = World:make_slot_mask(7, 11, 12, 14, 16, 17, 18, 21, 22, 25, 26, 33, 34, 35) + (shoot_through_shield and 8 or 7)
			wep_base._can_shoot_through_shield = true
		elseif wep_base._bullet_class.id == "explosive" or wep_base._bullet_class.id == "flame" or wep_base._bullet_class.id == "instant" and table.contains(tweak.categories, "grenade_launcher") then
			wep_base._can_shoot_through_shield = true
		end

		for _, unit in pairs(World:find_units("camera_cone", camera:camera_object(), Vector3(0, 0), (fov / 180 * 2), (max_distance > 0 and max_distance or special_wep and tweak.flame_max_range or tweak.damage_near or 7000), get_mask())) do
			local body = unit:get_object(Idstring(always_headshot and "Head" or body_map[math.random(1, #body_map)])) or unit:get_object(Idstring("a_detect"))
			local head_pos = body and body:position() or Vector3()
			local direction = Vector3()
			local behind_wall = not shoot_through_wall and unit:raycast("ray", head_pos, camera_position, "slot_mask", wep_base._bullet_slotmask, "thickness", 1, "thickness_mask", managers.slot:get_mask("world_geometry", "vehicles"))
			local behind_shield = unit:raycast("ray", head_pos, camera_position, "slot_mask", managers.slot:get_mask("enemy_shield_check"))
			local is_shield_and_wall = behind_shield and unit:raycast("ray", head_pos, camera_position, "slot_mask", managers.slot:get_mask("world_geometry", "vehicles"))
			local is_wall = behind_wall and not behind_shield and (not unit:in_slot(25, 26) or is_sentry_gun_active(unit))
			local is_shield = behind_shield and (not shoot_through_wall and not wep_base._can_shoot_through_shield or not shoot_through_shield or is_wall)

			mvector3.direction(direction, camera_position, head_pos)
			count[#count + 1] = {dir = direction, target = unit}
			if is_hostage(unit) or is_shield or is_wall or is_shield_and_wall then
				count[#count] = nil
			elseif draw_targets then
				Application:draw_arrow(player_unit:position(), head_pos + unit:rotation():y() * 20, 250, 10, 10, 0.5)
				Application:draw(unit, 250, 10, 10)
			end
		end
		return target_priority == 1 and count[1] or target_priority == 2 and count[#count] or target_priority == 3 and next(count) and count[math.random(1, #count)]
	end

	local function press_fire(state, t)
		local input = state:_get_input(0, 0, false)
		input.btn_primary_attack_press = true
		input.btn_primary_attack_state = true
		state:_check_action_primary_attack(t, input)
		input = state:_get_input(0, 0, false)
		input.btn_primary_attack_release = true
		return state:_check_action_primary_attack(t, input)
	end

	local function can_shoot(wep_base, tweak, state, t)
		local low_ammo = wep_base:get_ammo_remaining_in_clip() <= 0
		local can_refresh = table.contains(tweak.categories, "revolver") or auto_replenish_ammo
		if low_ammo and auto_reload and can_refresh then wep_base:replenish() end
		return low_ammo and auto_reload and press_fire(state, t) or not low_ammo and true
	end

	local old_enemy_update = EnemyManager.update
	function EnemyManager:update(t, dt)
		old_enemy_update(self, t, dt)

		local state = c.active and managers.player:get_current_state() or {}
		local equipped_unit = state._equipped_unit
		local wep_base = equipped_unit and equipped_unit:base()
		c.player_unit = managers.player:player_unit()

		if not equipped_unit or wep_base:get_ammo_total() <= 0 then 
			return
		end

		local tweak = wep_base:weapon_tweak_data()
		local special_wep = table.contains_any(tweak.categories, special_weapons)
		c.unit = get_target(c.player_unit, wep_base, tweak, special_wep) or {}

		if key_pressed() then
			return
		end
		
		c.unit_base = c.unit.target and c.unit.target.base and c.unit.target:base() or {}
		local rng_delay, min_delay, max_delay = get_fire_delay(wep_base)
		c.fire_delay_interval = c.fire_delay_interval or t + min_delay

		if c.unit.dir and c.fire_delay_interval <= t then
			c.fire_delay_on_target = c.fire_delay_on_target or {}
			if not c.fire_delay_on_target[c.unit.target:key()] or c.fire_delay_on_target[c.unit.target:key()] <= t then
				c.fire_delay_on_target[c.unit.target:key()] = t + max_delay
				local is_ready = can_shoot(wep_base, tweak, state, t)

				if is_ready and (special_wep or silent_shooting) then
					wep_base:trigger_held(c.player_unit:camera():position(), c.unit.dir, hit_damage(c.unit_base, wep_base._current_stats.damage or 0), nil, 0, 0, 0)
					managers.hud:set_ammo_amount(wep_base:selection_index(), wep_base:ammo_info())
				elseif is_ready then
					press_fire(state, t)
				end
			end
			c.fire_delay_interval = t + rng_delay
		end
	end

	local old_fire = NewRaycastWeaponBase.fire
	function NewRaycastWeaponBase:fire(from_pos, direction, dmg_mul, shoot_player, spread_mul, autohit_mul, suppr_mul, target_unit)
		if c.active and not silent_shooting and c.unit.dir and not key_pressed() and self._setup.user_unit and (self._setup.user_unit == c.player_unit) then
			return old_fire(self, from_pos, c.unit.dir, hit_damage(c.unit_base, dmg_mul), shoot_player, 0, autohit_mul, suppr_mul, target_unit)
		end
		return old_fire(self, from_pos, direction, dmg_mul, shoot_player, spread_mul, autohit_mul, suppr_mul, target_unit) 
	end

	local orig_hit_accuracy = StatisticsManager.hit_accuracy
	function StatisticsManager:hit_accuracy(...)
		local acc = orig_hit_accuracy(self, ...)
		c.accuracy = c.accuracy or acc
		if not c.active then c.accuracy = acc end
		return freeze_accuracy and c.active and c.accuracy or acc
	end

	local orig_session_hit_accuracy = StatisticsManager.session_hit_accuracy
	function StatisticsManager:session_hit_accuracy(...)
		local acc = orig_session_hit_accuracy(self, ...)
		c.session_accuracy = c.session_accuracy or acc
		if not c.active then c.session_accuracy = acc end
		return freeze_accuracy and c.active and c.session_accuracy or acc
	end
end
