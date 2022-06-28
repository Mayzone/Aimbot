local mod_name = "Mayzones_Aimbot"
local loaded = rawget(_G, mod_name)
local c = loaded or rawset(_G, mod_name, {
	draw_targets = true,									-- Outlines targets with arrow and box
	freeze_accuracy = false,								-- When aimbot is active, freezes the accuracy until, aimbot is off.
	target_priority = 1,									-- Set to 1 to target closest, 2 for furthest and 3 for random
	always_headshot = true,									-- Or a random bodypart
	auto_replenish_ammo = false,							-- Replenish ammo when emety by cheating ammo, requires auto_reload true.
	auto_reload = true,										-- Set to true to reload weapon when emety.
	shoot_through_wall = false,								-- Set to true if you want to target enemies through walls
	shoot_through_shield = true,							-- Set to true to shoot through shields when using special ammo or not shoot shields.
	silent_shooting = false,
	fov = 100,												-- 1-180. 135 recommended for whole screen as the fov is a cone from your camera and this is the cone width
	max_distance = 1500,									-- max distance, 0 for weapon range if possible or it's gona be 7000m

	fire_delay = 0.07,										-- Adds fire delay on top of weapons fire delay
	fire_delay_for_bows = false,								-- Set to false ot ignore fire_delay value
	custom_damage_by_unit = false,							-- Set to true to use defined damage by unit in table bellow or false, this has priority 1.
	custom_damage = false,									-- Custom damage in number format or false. Prioritizing custom_damage_by_unit first.

	shoot_civilians = false,								-- Set to true to shoot civilians.
	shoot_turrets = true,									-- Set to true to shoot turrets, shoot_through_wall is requires.
	shoot_enemies = true,									-- Set to true to shoot enemies.

	shoot_when_moving = true,								-- set to true to auto shoot when moving. 
	shoot_when_aiming = false,								-- set to true to auto shoot when aiming down sight.
	shoot_when_running = true,								-- set to true to auto shoot when running.
	shoot_when_crouching = true,							-- set to true to auto shoot when crouching.
	shoot_when_keybind_is_pressed = {},						-- set "left shift", "right shift", "left ctrl", "right ctrl", "left alt", "t", "g", "4" for mouse 4/number 4 and "mouse wheel up" e.g to auto shoot. {"left shift", "right shift"} e.g
	aim_head_when_keybind_is_pressed = "",					-- set "left shift", "right shift", "left ctrl", "right ctrl", "left alt", "t", "g", "4" for mouse 4/number 4 and "mouse wheel up" e.g to auto shoot. Requires always_headshot = false

	state_blacklist = {										-- Set to true to shoot in those states
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
	},
	custom_damage_table = {
		["phalanx_minion"]						= 1000, 	-- Wintergoons
		["tank"]								= false
	},
	fire_delay_by_unit = {
		["tank"]								= 0,
		["tank_mini"]							= 0,		-- Minigundozer
		["tank_medic"]							= 0,		-- Medic Dozer
		["tank_hw"]								= 0,		-- Headless Titandozers
		["sentry_gun"]							= 0			-- enemy sentry
	},
	blocked_units = {										-- Set to true to block shooting those units
		["triad_boss"]							= true,		-- mountain master triad boss
		["triad_boss_no_armor"]					= true,		-- mountain master triad boss with no armor
		["phalanx_vip"]							= true		-- captain winter
	}
}) and _G[mod_name]

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
		duck = not c.shoot_when_crouching, run = not c.shoot_when_running, secondary_attack = not c.shoot_when_aiming
	}

	function c:get_fire_delay(weap_base)
		local fire_rate_data = weap_base:recoil_wait() or weap_base:fire_mode() == "single" and 0.6 or self.fire_delay
		local unit_fire_rate = self.fire_delay_by_unit[self.unit_base._tweak_table] or self.unit_base.sentry_gun and self.fire_delay_by_unit["sentry_gun"]
		local min_rate = (unit_fire_rate or self.fire_delay) + fire_rate_data
		local max_rate = (unit_fire_rate or self.fire_delay) + fire_rate_data / 3
		return math.random()*(max_rate-min_rate) + min_rate, min_rate, max_rate
	end

	function c:key_pressed(key)
		if (Input:keyboard():down(Idstring(key)) or Input:mouse():down(Idstring(key))) then
			return true
		end
	end

	function c:can_not_shoot()
		local controller = self.player_unit and self.player_unit:base() and self.player_unit:base():controller()
		local active_menu, can_shoot = managers.menu._open_menus[#managers.menu._open_menus], true

		if not self.state_blacklist[managers.player._current_state]
		or managers.hud and managers.hud._chat_focus == true
		or active_menu and active_menu.name == "menu_pause"
		or managers.network.account and managers.network.account._overlay_opened
		or controller and mvector3.length(controller:get_input_axis("move")) > PlayerStandard.MOVEMENT_DEADZONE and not self.shoot_when_moving then
			return true
		end

		for _, v in pairs(self.shoot_when_keybind_is_pressed) do
			can_shoot = false
			if self:key_pressed(v) then
				can_shoot = true; break
			end
		end

		for k, v in pairs(controlls) do
			if v and (controller:get_input_pressed(k) or controller:get_input_bool(k)) or not can_shoot then
				return true
			end
		end
	end

	function c:aim_at_head()
		if #self.aim_head_when_keybind_is_pressed > 0 and self:key_pressed(self.aim_head_when_keybind_is_pressed) then
			return true
		end
	end

	function c:hit_damage(base, dmg)
		return self.custom_damage_by_unit and self.custom_damage_table[base._tweak_table] and self.custom_damage_table[base._tweak_table] / 100 or self.custom_damage and self.custom_damage / 100 or dmg
	end

	function c:is_sentry_gun_active(unit)
		local movement = unit:movement()
		local turret_states = {active = true, rearming = true, activating = true}
		return type(movement) == "table" and turret_states[movement._state] ~= nil
	end

	function c:is_hostage(unit)
		local brain = alive(unit) and unit.brain and unit:brain()
		local char_dmg = brain and unit:character_damage()
		local anim = unit:anim_data() -- for hostage trade
		if self.blocked_units[unit:base()._tweak_table] or player_sentries[unit:name():t()] or char_dmg and (char_dmg._dead or char_dmg._invulnerable or char_dmg._immortal or char_dmg._god_mode) or brain.is_hostage and brain:is_hostage() or not brain:is_hostile() or anim and (anim.hands_tied or anim.tied) then
			return true
		end
	end

	function c:get_mask()
		local masks = {}
		masks[#masks + 1] = self.shoot_enemies and "enemies" or nil
		masks[#masks + 1] = self.shoot_civilians and "civilians" or nil
		masks[#masks + 1] = self.shoot_turrets and "sentry_gun" or nil
		return managers.slot:get_mask(unpack(masks))
	end

	function c:get_target(player_unit, weap_base, tweak, special_wep)
		local count = {}
		local camera = player_unit:camera()
		local camera_position = camera:position()

		if self.shoot_through_wall then
			weap_base._bullet_slotmask = World:make_slot_mask(7, 11, 12, 14, 16, 17, 18, 21, 22, 25, 26, 33, 34, 35) + (self.shoot_through_shield and 8 or 7)
			weap_base._can_shoot_through_shield = true
		elseif weap_base._bullet_class.id == "explosive" or weap_base._bullet_class.id == "flame" or weap_base._bullet_class.id == "instant" and table.contains(tweak.categories, "grenade_launcher") then
			weap_base._can_shoot_through_shield = true
		end

		for _, unit in pairs(World:find_units("camera_cone", camera:camera_object(), Vector3(0, 0), (self.fov / 180 * 2), (self.max_distance > 0 and self.max_distance or special_wep and tweak.flame_max_range or tweak.damage_near or 7000), self:get_mask())) do
			local body = unit:get_object(Idstring((self.always_headshot or self:aim_at_head()) and "Head" or body_map[math.random(1, #body_map)])) or unit:get_object(Idstring("a_detect"))
			local head_pos = body and body:position() or Vector3()
			local direction = Vector3()
			local behind_wall = not self.shoot_through_wall and unit:raycast("ray", head_pos, camera_position, "slot_mask", weap_base._bullet_slotmask, "thickness", 1, "thickness_mask", managers.slot:get_mask("world_geometry", "vehicles"))
			local behind_shield = unit:raycast("ray", head_pos, camera_position, "slot_mask", managers.slot:get_mask("enemy_shield_check"))
			local is_shield_and_wall = behind_shield and unit:raycast("ray", head_pos, camera_position, "slot_mask", managers.slot:get_mask("world_geometry", "vehicles"))
			local is_wall = behind_wall and not behind_shield and (not unit:in_slot(25, 26) or self:is_sentry_gun_active(unit))
			local is_shield = behind_shield and (not self.shoot_through_wall and not weap_base._can_shoot_through_shield or not self.shoot_through_shield or is_wall)

			mvector3.direction(direction, camera_position, head_pos)
			count[#count + 1] = {dir = direction, target = unit}
			if self:is_hostage(unit) or is_shield or is_wall or is_shield_and_wall then
				count[#count] = nil
			elseif self.draw_targets then
				Application:draw_arrow(player_unit:position(), head_pos + unit:rotation():y() * 20, 250, 10, 10, 0.5)
				Application:draw(unit, 250, 10, 10)
			end
		end
		return self.target_priority == 1 and count[1] or self.target_priority == 2 and count[#count] or self.target_priority == 3 and next(count) and count[math.random(1, #count)]
	end

	function c:press_fire(state, t)
		local input = state:_get_input(0, 0, false)
		input.btn_primary_attack_press = true
		input.btn_primary_attack_state = true
		state:_check_action_primary_attack(t, input)
		input = state:_get_input(0, 0, false)
		input.btn_primary_attack_release = true
		return state:_check_action_primary_attack(t, input)
	end

	function c:can_shoot(weap_base, tweak, state, t)
		local low_ammo = weap_base:get_ammo_remaining_in_clip() <= 0
		local can_refresh = table.contains(tweak.categories, "revolver") or self.auto_replenish_ammo
		if low_ammo and self.auto_reload and can_refresh then weap_base:replenish() end
		return low_ammo and self.auto_reload and self:press_fire(state, t) or not low_ammo and true
	end

	local old_enemy_update = EnemyManager.update
	function EnemyManager:update(t, dt)
		old_enemy_update(self, t, dt)

		local state = c.active and managers.player:get_current_state() or {}
		local equipped_unit = state._equipped_unit
		local weap_base = equipped_unit and equipped_unit:base()

		if not weap_base or weap_base:get_ammo_total() <= 0 then 
			return
		end

		local tweak = weap_base:weapon_tweak_data()
		local special_wep = table.contains_any(tweak.categories, special_weapons)
		c.player_unit = managers.player:player_unit()
		c.unit = c:get_target(c.player_unit, weap_base, tweak, special_wep) or {}

		if c:can_not_shoot() then
			return
		end
		
		c.unit_base = c.unit.target and c.unit.target.base and c.unit.target:base() or {}
		local rng_delay, min_delay, max_delay = c:get_fire_delay(weap_base)
		c.fire_delay_interval = c.fire_delay_interval or t + min_delay

		if c.unit.dir and c.fire_delay_interval <= t then
			c.fire_delay_on_target = c.fire_delay_on_target or {}

			if not c.fire_delay_on_target[c.unit.target:key()] or c.fire_delay_on_target[c.unit.target:key()] <= t then
				c.fire_delay_on_target[c.unit.target:key()] = t + max_delay
				local is_ready = c:can_shoot(weap_base, tweak, state, t)

				if is_ready then
					if (special_wep or c.silent_shooting) then
						local charging_weapon, cam_pos, dmg = weap_base:fire_on_release() and weap_base:charging(), c.player_unit:camera():position(), c:hit_damage(c.unit_base, weap_base._current_stats.damage or 0)

						weap_base:trigger_held(cam_pos, c.unit.dir, dmg, nil, 0, 0, 0)

						--[[ For bow charge
						if not state.charging_weapon and charging_weapon then
							state:_start_action_charging_weapon(t)
						elseif state.charging_weapon and not charging_weapon then
							state:_end_action_charging_weapon(t)
						end--]]

						if charging_weapon and not weap_base._cancelled then
							if not c.fire_delay_for_bows then
								c.fire_delay = 0
							end

							if weap_base:charge_multiplier() >= (state._unit:anim_length(Idstring("charge")) or weap_base:charge_max_t() / 1.5) then
								weap_base:trigger_released(cam_pos, c.unit.dir, dmg, nil, 0, 0, 0)
							end
						end

						managers.hud:set_ammo_amount(weap_base:selection_index(), weap_base:ammo_info())
					else
						c:press_fire(state, t)
					end
				end
			end
			c.fire_delay_interval = t + rng_delay
		end
	end

	local old_fire = NewRaycastWeaponBase.fire
	function NewRaycastWeaponBase:fire(from_pos, direction, dmg_mul, shoot_player, spread_mul, autohit_mul, suppr_mul, target_unit)
		if c.active and not c.silent_shooting and c.unit.dir and not c:can_not_shoot() and self._setup.user_unit and (self._setup.user_unit == c.player_unit) then
			return old_fire(self, from_pos, c.unit.dir, c:hit_damage(c.unit_base, dmg_mul), shoot_player, 0, autohit_mul, suppr_mul, target_unit)
		end
		return old_fire(self, from_pos, direction, dmg_mul, shoot_player, spread_mul, autohit_mul, suppr_mul, target_unit) 
	end

	local orig_hit_accuracy = StatisticsManager.hit_accuracy
	function StatisticsManager:hit_accuracy(...)
		local acc = orig_hit_accuracy(self, ...)
		c.accuracy = c.accuracy or acc
		if not c.active then c.accuracy = acc end
		return c.freeze_accuracy and c.active and c.accuracy or acc
	end

	local orig_session_hit_accuracy = StatisticsManager.session_hit_accuracy
	function StatisticsManager:session_hit_accuracy(...)
		local acc = orig_session_hit_accuracy(self, ...)
		c.session_accuracy = c.session_accuracy or acc
		if not c.active then c.session_accuracy = acc end
		return c.freeze_accuracy and c.active and c.session_accuracy or acc
	end
else
	rawset(_G, mod_name, nil)
end
