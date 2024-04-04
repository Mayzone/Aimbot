--[[ notes

]]--

local mod_name = "Mayzones_Aimbot"
local loaded = rawget(_G, mod_name)
local c = loaded or rawset(_G, mod_name, {}) and _G[mod_name]

if not loaded then
	function c:init()
		math.randomseed(os.time())
		
		self.config = {}
		self.path = "mods/crosshair assist/%s"
		
		if not self:load_config() then
			return
		end
		
		self.unit_colors = {}
		self.player_sentries = {["@IDc71d763cd8d33588@"] = true, ["@IDb1f544e379409e6c@"] = true, ["@ID2cf4f276ce7ba6f5@"] = true, ["@ID07bd083cc5f2d3ba@"] = true}
		self.special_weapons = {"flamethrower", "bow"}
		self.body_map = {
			"Hips","Spine","Spine1","Spine2","Neck","Head",
			"LeftShoulder","LeftArm","LeftForeArm","RightShoulder","RightArm","RightForeArm",
			"LeftUpLeg","LeftLeg","LeftFoot","RightUpLeg","RightLeg","RightFoot"
		}
		self.controlls = {
			primary_attack = true, throw_grenade = true, reload = true,
			switch_weapon = true, jump = true, interact = true, 
			use_item = true, melee = true, secondary_attack = not self.config.shoot_when_aiming
		}
		self.dmg_types = {
			"damage_melee", "damage_bullet", "damage_fire",
			"damage_explosion", "damage_dot", "damage_simple"
		}
		
		self:set_projectile_speed()
		
		return true
	end

	function c:load_config()
		dofile(string.format(self.path, "JSON.lua"))
		local file = self.JSON and self.JSON:jsonFile(string.format(self.path, "config.json"))
        if file then
			for _, v in pairs(self.JSON:decode(file)) do
				self.config = v
			end
			return true
        end
	end

	function c:save_config()
		local file = self.JSON and io.open(string.format(self.path, "config.json"), "w")
        if file then
            file:write(self.JSON:encode_pretty({config = self.config}))
            file:close()
        end
	end

	function c:set_projectile_speed()
		self.orig_projectile_speed = {}

		for _, projectile in pairs(tweak_data.blackmarket:get_projectiles_index() or {}) do
			if type(projectile) == "string" and type(tweak_data.projectiles[projectile]) == "table" and projectile:lower():match("arrow") then
				self.orig_projectile_speed[projectile] = self.orig_projectile_speed[projectile] or {}
				self.orig_projectile_speed[projectile]["launch_speed"] = tweak_data.projectiles[projectile].launch_speed
				tweak_data.projectiles[projectile].no_cheat_count = true
				tweak_data.projectiles[projectile].launch_speed = (tweak_data.projectiles[projectile].launch_speed or 2000) * 1.6
			end
		end
	end

	function c:reload(unload, load)
		if unload then
			self.safe_load = true

			self.temp_orig_func_table = self.temp_orig_func_table or {}
			for _, func_name in pairs(self.dmg_types) do
				self.temp_orig_func_table[func_name] = CopDamage[func_name]
				CopDamage[func_name] = self.orig_func_table[func_name]
			end

			self.temp_orig_upgrade_value = PlayerManager.upgrade_value
            PlayerManager.upgrade_value = self.orig_upgrade_value

			self.temp_orig_send_melee_attack_result = CopDamage._send_melee_attack_result
            CopDamage._send_melee_attack_result = self.orig_send_melee_attack_result

            self.temp_orig_enemy_update = EnemyManager.update
            EnemyManager.update = self.orig_enemy_update
			
			self.temp_orig_fire = NewRaycastWeaponBase.fire
            NewRaycastWeaponBase.fire = self.orig_fire
			
			self.temp_orig_hit_accuracy = StatisticsManager.hit_accuracy
            StatisticsManager.hit_accuracy = self.orig_hit_accuracy
			
			self.temp_orig_session_hit_accuracy = StatisticsManager.session_hit_accuracy
            StatisticsManager.session_hit_accuracy = self.orig_session_hit_accuracy
			
			self.temp_orig_set_rotation = PlayerCamera.set_rotation
            PlayerCamera.set_rotation = self.orig_set_rotation

			for projectile in pairs(c.orig_projectile_speed) do
				tweak_data.projectiles[projectile]["launch_speed"] = self.orig_projectile_speed[projectile].launch_speed
			end
        end
        
        if load and self.safe_load then
			for _, func_name in pairs(self.dmg_types) do
				CopDamage[func_name] = self.temp_orig_func_table[func_name]
			end
            PlayerManager.upgrade_value = self.temp_orig_upgrade_value
			CopDamage._send_melee_attack_result = self.temp_orig_send_melee_attack_result
            EnemyManager.update = self.temp_orig_enemy_update
			NewRaycastWeaponBase.fire = self.temp_orig_fire
			StatisticsManager.hit_accuracy = self.temp_orig_hit_accuracy
			StatisticsManager.session_hit_accuracy = self.temp_orig_session_hit_accuracy
			PlayerCamera.set_rotation = self.temp_orig_set_rotation
			self:set_projectile_speed()
        end
	end

	function c:get_fire_delay(weap_base)
		local fireRateData = weap_base:recoil_wait() or (weap_base:fire_mode() == "single" and 0.6) or self.config.fire_delay
		local unitFireRate = self.config.fire_delay_by_unit[self.unit_base._tweak_table] or (self.unit_base.sentry_gun and self.config.fire_delay_by_unit["sentry_gun"])
		local minRate = (unitFireRate or self.config.fire_delay) + fireRateData
		local maxRate = (unitFireRate or self.config.fire_delay) + fireRateData / 3
		local randomDelay = math.random() * (maxRate - minRate) + minRate
	
		if not self.config.fire_delay_for_bows then
			minRate = 0
			maxRate = 0
		end

		return randomDelay, minRate, maxRate
	end

	function c:key_pressed(key, kb_mouse, predefined)
		if kb_mouse and (Input:keyboard():down(Idstring(key)) or Input:mouse():down(Idstring(key))) then
			return true
		end
		
		if predefined and self.controller and (self.controller:get_input_pressed(key) or self.controller:get_input_bool(key)) then
			return true
		end
	end

	function c:can_not_shoot()
		self.controller = self.player_unit and self.player_unit:base() and self.player_unit:base():controller()
		local isChatOpen = managers.hud and managers.hud._chat_focus == true
		local activeMenu = managers.menu._open_menus[#managers.menu._open_menus]
		local isPauseMenuOpen = activeMenu and activeMenu.name == "menu_pause"
		local isOverlayOpened = managers.network.account and managers.network.account._overlay_opened or self.player_unit:base():stats_screen_visible()
		local isRestrictedState = not self.config.state_blacklist[managers.player._current_state]
		local isMoving = self.controller and mvector3.length(self.controller:get_input_axis("move")) > PlayerStandard.MOVEMENT_DEADZONE and not self.config.shoot_when_moving
	
		local isKeybindNotPressed = false 
		for _, v in pairs(self.config.shoot_when_keybind_is_pressed) do -- Check if any keybinds for shooting are pressed
			if not self:key_pressed(v, true, true) or not self.config.shoot_when_aiming and self:key_pressed(v, true, true) then
				isKeybindNotPressed = true
				break
			end
		end
	
		local isControlPressed = false
		for k, v in pairs(self.controlls) do -- Check if any control keys are pressed that restrict shooting
			if v and self:key_pressed(k, false, true) then
				isControlPressed = true
				break
			end
		end
	
		return isRestrictedState or isChatOpen or isPauseMenuOpen or isOverlayOpened or isMoving or isKeybindNotPressed or isControlPressed
	end

	function c:aim_at_head(unit, player)
		if #self.config.aim_head_when_keybind_is_pressed > 0 and self:key_pressed(self.config.aim_head_when_keybind_is_pressed, true, true) then
			local player_camera, angle = player:camera(), Rotation:look_at(unit.dir, math.UP)
	        player_camera:set_rotation(angle) -- Lock player angle on target
			player_camera:camera_unit():base():set_rotation(angle) -- Lock weapon angle on target

			return true
		end
	end

	function c:hit_damage(base, dmg)
		return self.config.custom_damage_by_unit and self.config.custom_damage_table[base._tweak_table] and self.config.custom_damage_table[base._tweak_table] / 100 or self.config.custom_damage and self.config.custom_damage / 100 or dmg
	end

	function c:is_sentry_gun_active(unit)
		local movement = unit:movement()
		local turret_states = {active = true, rearming = true, activating = true}
		return type(movement) == "table" and turret_states[movement._state] ~= nil
	end

	function c:is_hostage(unit)
		if not alive(unit) then
			return 
		end

		for peer_id, peer in pairs(self.config.shoot_players and managers.network:session():peers() or {}) do
			local peer_unit = peer:unit()
			if alive(peer_unit) and peer_unit:key() == unit:key() then
				local peer_state = peer_unit:movement()._state
				return peer_state and not self.config.state_blacklist[peer_state]
			end
		end

		local brain = alive(unit) and unit.brain and unit:brain()
		local char_dmg = brain and unit:character_damage()
		local anim = unit.anim_data and unit:anim_data() or {} -- for hostage trade
		if self.config.blocked_units[unit:base()._tweak_table] or self.player_sentries[unit:name():t()] or char_dmg and (char_dmg._dead or char_dmg._invulnerable or char_dmg._immortal or char_dmg._god_mode) or brain and (brain.is_hostage and brain:is_hostage() or brain.is_hostile and not brain:is_hostile()) or anim and (anim.hands_tied or anim.tied) then
			return true
		end
	end

	function c:get_mask()
		local masks = {}
		masks[#masks + 1] = self.config.shoot_enemies and "enemies" or nil
		masks[#masks + 1] = self.config.shoot_civilians and "civilians" or nil
		masks[#masks + 1] = self.config.shoot_turrets and "sentry_gun" or nil
		masks[#masks + 1] = self.config.shoot_players and "criminals" or nil
		return managers.slot:get_mask(unpack(masks)) + World:make_slot_mask(self.config.shoot_cameras and 1 or -1)
	end

	function c:calculateFov()
		local aspectRatio = RenderSettings.aspect_ratio or 1.77777777
		local fovRadians = math.rad(self.config.fov)
		local horizontalFov = 2 * math.atan(math.tan(fovRadians / 2) * aspectRatio)
		local verticalFov = 2 * math.atan(math.tan(fovRadians / 2) / aspectRatio)
		horizontalFov = math.min(horizontalFov, math.rad(360))
		verticalFov = math.min(verticalFov, math.rad(360))
	
		return math.max(horizontalFov, verticalFov) / 2
	end

	function c:get_target(player_unit, weap_base, tweak, special_wep)
		local count = {}
		local camera = player_unit:camera()
		local camera_position = camera:position()
		self.orig_bullet_slot_mask = self.orig_bullet_slot_mask or weap_base._bullet_slotmask
		weap_base._bullet_slotmask = self.orig_bullet_slot_mask
		weap_base._can_shoot_through_shield = false

		if self.config.shoot_through_wall then
			weap_base._bullet_slotmask = World:make_slot_mask(7, 11, 12, 14, 15, 16, 17, 18, 21, 22, 25, 26, 33, 34, 35, 37, 39) + (self.config.shoot_through_shield and 8 or -1)
			weap_base._can_shoot_through_shield = true
		elseif weap_base._bullet_class.id == "explosive" or weap_base._bullet_class.id == "flame" or weap_base._bullet_class.id == "instant" and table.contains(tweak.categories, "grenade_launcher") or self.config.shoot_through_shield and not weap_base._can_shoot_through_shield then
			weap_base._can_shoot_through_shield = true
		end

		for _, unit in pairs(World:find_units("camera_cone", camera:camera_object(), Vector3(0, 0), self:calculateFov(), (self.config.max_distance > 0 and self.config.max_distance or special_wep and tweak.flame_max_range or tweak.damage_near or 7000), self:get_mask())) do
			local in_camera_slot = unit:in_slot(1)
			local is_camera = in_camera_slot and unit:base() and unit:base().is_security_camera
			local is_titan_camera = is_camera and managers.job:current_difficulty_stars() > 3
			local body = unit:get_object(Idstring(is_camera and "CameraLens" or self.config.always_headshot and "Head" or special_wep and "Hips" or self.body_map[math.random(1, #self.body_map)])) or unit:get_object(Idstring("a_detect"))
			local aim_pos = body and body:position() or Vector3()
			local behind_wall = not self.config.shoot_through_wall and unit:raycast("ray", aim_pos, camera_position, "slot_mask", weap_base._bullet_slotmask, "thickness", 1, "thickness_mask", managers.slot:get_mask("world_geometry", "vehicles"))
			local behind_shield = unit:raycast("ray", aim_pos, camera_position, "slot_mask", managers.slot:get_mask("enemy_shield_check"))
			local is_shield_and_wall = behind_shield and unit:raycast("ray", aim_pos, camera_position, "slot_mask", managers.slot:get_mask("world_geometry", "vehicles"))
			local is_wall = behind_wall and not behind_shield and (not unit:in_slot(25, 26) or self:is_sentry_gun_active(unit))
			local is_shield = behind_shield and (not self.config.shoot_through_wall and not weap_base._can_shoot_through_shield or not self.config.shoot_through_shield or is_wall)
			local unit_id = unit:id()
			self.unit_colors[unit_id] = self.unit_colors[unit_id] or {r = math.random(), g = math.random(), b = math.random()}
			local colors = self.unit_colors[unit_id]

			count[#count + 1] = {dir = (aim_pos - camera_position):normalized(), target = unit, colors = colors, aim_pos = aim_pos, camera_position = camera_position}

			if in_camera_slot and not is_camera or is_camera and self.config.shoot_through_wall or is_titan_camera and self.config.shoot_cameras or self:is_hostage(unit) or is_shield or is_wall or is_shield_and_wall then
				count[#count] = nil
			else
				if self.config.xray_targets and unit.contour and unit:contour() then
					if is_camera and not unit:contour():has_id("mark_unit") then
						unit:contour():add("mark_unit", false, 20)
					elseif not unit:contour():has_id("mark_enemy") then
						unit:contour():add("mark_enemy", false, 20)
					end

					for _, material in ipairs(unit:contour()._materials or unit:get_objects_by_type(Idstring("material")) or {}) do
						material:set_variable(Idstring("contour_color"), Color(colors.r, colors.g, colors.b))
					end
				end

				if self.config.draw_targets then
					Application:draw(unit, colors.r, colors.g, colors.b)
				end
			end
		end

		return self.config.target_priority == 1 and count[1] or self.config.target_priority == 2 and count[#count] or self.config.target_priority == 3 and next(count) and count[math.random(1, #count)]
	end

	function c:press_fire(state, t)
		local input = state:_get_input(0, 0, false)
		input.btn_primary_attack_press = true
		input.btn_primary_attack_state = true
		state:_check_action_primary_attack(t, input)
	
		input = state:_get_input(0, 0, false)
		input.btn_primary_attack_release = true
		state:_check_action_primary_attack(t, input)
	end

	function c:can_shoot(weap_base, tweak, state, t, is_special_weapon)
		local low_ammo = weap_base:get_ammo_remaining_in_clip() <= 0
		local can_refresh = table.contains(tweak.categories, "revolver") or self.config.replenish_ammo
	
		if low_ammo and self.config.auto_reload then
			if can_refresh then
				weap_base:replenish()
			end

			if self.config.silent_ghost or is_special_weapon then
				self:press_fire(state, t)
			end
		end
	
		return low_ammo and self.config.auto_reload or not low_ammo
	end
	
	function c:print_desc(toggle, title, text, desc)
		self.desc = title .. ": " .. desc

		if #text > 0 then
			managers.chat:_receive_message(1, title, text, (toggle and Color.green or Color.red))
		end
	end
	
	function c:open_aimbot_config()
		local options = {
			{name = "Silent Ghost", value = self.config.silent_ghost, description = "Gunfire will not make noise, you ignore pagers and become invisible."},
			{name = "Draw Targets", value = self.config.draw_targets, description = "Toggle drawing outlines around targets."},
			{name = "Xray Targets", value = self.config.xray_targets, description = "Toggle x-ray vision to see targets through walls."},
			{name = "Always Headshot", value = self.config.always_headshot, description = "Always aim for the head."},
			{name = "Replenish Ammo", value = self.config.replenish_ammo, description = "Automatically replenish ammo when empty."},
			{name = "Auto Reload", value = self.config.auto_reload, description = "Automatically reload when out of ammo."},
			{name = "Freeze Accuracy", value = self.config.freeze_accuracy, description = "Freeze your weapons accuracy at a percentage."},
			{name = "Inverted Look Direction", value = self.config.inverted_look_direction, description = "Pitch and yaw is inverted so other players will not see where you look."},
			{name = "Angle Restriction", value = self.config.angle_restriction, description = "Restrict yaw, pitch and roll to max 45 degree for other players."},
			{name = "Spin Player", value = self.config.spin_player, description = "Spinbot for other players."},
			{name = "Fake Lag", value = self.config.fake_lag, description = "Jitter and lag for other players."},
			{name = "Shoot Through Wall", value = self.config.shoot_through_wall, description = "When not, your ammo is determining it."},
			{name = "Shoot Through Shield", value = self.config.shoot_through_shield, description = "When not, your ammo is determining it."},
			{name = "Shoot Civilians", value = self.config.shoot_civilians, description = "Toggle shooting civilians."},
			{name = "Shoot Turrets", value = self.config.shoot_turrets, description = "Toggle shooting enemy turrets."},
			{name = "Shoot Enemies", value = self.config.shoot_enemies, description = "Toggle shooting enemies."},
			{name = "Shoot Players", value = self.config.shoot_players, description = "Toggle shooting other players."},
			{name = "Shoot Cameras", value = self.config.shoot_cameras, description = "Shoot cameras if shoot through wall is false."},
			{name = "Shoot When Moving", value = self.config.shoot_when_moving, description = "Toggle shooting while moving."},
			{name = "Shoot When Aiming", value = self.config.shoot_when_aiming, description = "Toggle shooting while aiming down sight."},
			{name = "Fire Delay For Bows", value = self.config.fire_delay_for_bows, description = "When activated, will make bows use the same fire delay as regular weapons."},
			{name = "Custom Damage By Unit", value = self.config.custom_damage_by_unit, description = "Uses custom damage on spesific units, changed in lua file. This damage has priority 1."}
		}
	
		local options_menu = {
			title = "Aimbot Config",
			text = self.desc or "Select Option",
			button_list = {}
		}
	
		table.insert(options_menu.button_list, {
			text = "Toggle Aimbot - " .. tostring((self.active or false)),
			callback_func = function()
				self.active = not self.active
				self:print_desc(self.active, "Aimbot", (self.active and "Activated" or "Deactivated"), "Activate or deactivate the aimbot.")
				self:reload(not self.active, self.active)
			end
		})
		table.insert(options_menu.button_list, {})

		for _, option in ipairs(options) do
			local text = option.name .. " - " .. tostring(option.value)
			table.insert(options_menu.button_list, {
				text = text,
				callback_func = function()
					option.value = not option.value
					self.config[option.name:lower():gsub(" ", "_")] = option.value
					self:save_config()
					self:print_desc(option.value, option.name, option.description, option.description)
				end
			})
		end

		table.insert(options_menu.button_list, {})
		table.insert(options_menu.button_list, {text = managers.localization:text("dialog_cancel"), cancel_button = true})
	
		managers.system_menu:show_buttons(options_menu)
	end
	
	if not c:init() then
		managers.chat:_receive_message(1, mod_name, "Error loading config.", Color.red)
		return rawset(_G, mod_name, nil)
	end

	local last_fire_time = 0
	c.orig_enemy_update = EnemyManager.update
	function EnemyManager:update(t, dt)
		c.orig_enemy_update(self, t, dt)

		if not c.active then
			return
		end

		c.player_unit = managers.player:player_unit()
		local player_movement = alive(c.player_unit) and c.player_unit:movement()

		if type(player_movement) == "table" and managers.groupai:state():whisper_mode() then
			if c.config.silent_ghost then
				player_movement:set_attention_settings({"pl_civilian"})
			else
				player_movement:set_attention_settings({"pl_mask_on_foe_combatant_whisper_mode_stand", "pl_mask_on_foe_combatant_whisper_mode_crouch"})
			end
		end

		local state = managers.player:get_current_state()
		local equipped_unit = state and state._equipped_unit
		local weap_base = equipped_unit and equipped_unit:base()

		if not weap_base or weap_base:get_ammo_total() <= 0 then
			return
		end

		local tweak = weap_base:weapon_tweak_data()
		local is_special_weapon = table.contains_any(tweak.categories, c.special_weapons)
		c.unit = c:get_target(c.player_unit, weap_base, tweak, special_wep) or {}

		if not c.unit.dir then
			return
		end

		if c.config.draw_targets then
			Application:draw_cylinder(c.unit.camera_position, c.unit.aim_pos, c:calculateFov()/3, 201/255, 19/255, 6/255)
		end

		if c:aim_at_head(c.unit, c.player_unit) or c:can_not_shoot() then
			return
		end

		if is_special_weapon and c.config.always_headshot then
			c.config.always_headshot = false
		end

		c.unit_base = c.unit.target and c.unit.target.base and c.unit.target:base() or {}
		local time_since_last_fire = t - last_fire_time
		local rng_delay, min_delay, max_delay = c:get_fire_delay(weap_base)

		if time_since_last_fire < (c.fire_delay_interval or max_delay) then
			return
		end

		if c:can_shoot(weap_base, tweak, state, t, is_special_weapon) then
			local is_silent_ghost = is_special_weapon or c.config.silent_ghost
			local charging_weapon = weap_base:fire_on_release() and weap_base:charging()
			local cam_pos = c.player_unit:camera():position()
			local damage = c:hit_damage(c.unit_base, weap_base._current_stats.damage or 0)

			if c.config.shoot_players and c.unit.target:in_slot(3) then
				local peer = managers.network:session():peer_by_unit(c.unit.target)

				if peer then
					local team_index = tweak_data.levels:get_team_index("converted_enemy")
					managers.network:session():send_to_peers("sync_unit_event_id_16", c.player_unit, "movement", team_index)
					managers.network:session():send_to_peers("sync_friendly_fire_damage", peer:id(), c.player_unit, managers.mutators:modify_value("HuskPlayerDamage:FriendlyFireDamage", damage), "bullet")
				end
			end

			if is_silent_ghost then
				c.orig_alert_size = c.orig_alert_size or weap_base._alert_size
				c.orig_panic_suppression_chance = c.orig_panic_suppression_chance or weap_base._panic_suppression_chance
				weap_base._alert_size = 0
				weap_base._panic_suppression_chance = 0

				if charging_weapon then
					local charge_max_t = math.max(weap_base:charge_max_t(), weap_base:reload_speed_multiplier())
					c.fire_delay_interval = charge_max_t
					weap_base:trigger_released(cam_pos, c.unit.dir, damage, nil, 0, 0, 0)
				else
					c.fire_delay_interval = rng_delay
					weap_base:trigger_held(cam_pos, c.unit.dir, damage, nil, 0, 0, 0)
				end

				managers.hud:set_ammo_amount(weap_base:selection_index(), weap_base:ammo_info())
			else
				weap_base._alert_size = c.orig_alert_size or weap_base._alert_size
				weap_base._panic_suppression_chance = c.orig_panic_suppression_chance or weap_base._panic_suppression_chance

				c:press_fire(state, t)
				c.fire_delay_interval = rng_delay
			end

			last_fire_time = t
		end
	end

	c.orig_func_table = c.orig_func_table or {}
	for _, func_name in pairs(c.dmg_types) do
		c.orig_func_table[func_name] = CopDamage[func_name]
		CopDamage[func_name] = function(self, attack_data, ...)
			if c.active and c.config.silent_ghost and managers.groupai:state():whisper_mode() then
				attack_data.variant = "melee"
				attack_data.name_id = "cqc"
				c.snitch_chance = 1
				return c.orig_func_table["damage_melee"](self, attack_data, ...)
			end
			c.snitch_chance = 0
			return c.orig_func_table[func_name](self, attack_data, ...)
		end
	end

	c.orig_upgrade_value = PlayerManager.upgrade_value
	function PlayerManager:upgrade_value(category, upgrade, ...)
		local original_value = c.orig_upgrade_value(self, category, upgrade, ...)
		if c.active and c.config.silent_ghost and category == "player" and upgrade == "melee_kill_snatch_pager_chance" then
			original_value = (original_value + (c.snitch_chance or 0))
		end
		return original_value
	end

	c.orig_send_melee_attack_result = CopDamage._send_melee_attack_result
	function CopDamage:_send_melee_attack_result(attack_data, damage_percent, damage_effect_percent, hit_offset_height, variant, body_index)
		if c.active and c.config.silent_ghost and managers.groupai:state():whisper_mode() then
			return c.orig_send_melee_attack_result(self, attack_data, damage_percent, damage_effect_percent, hit_offset_height, 3, body_index)
		end
		return c.orig_send_melee_attack_result(self, attack_data, damage_percent, damage_effect_percent, hit_offset_height, variant, body_index)
	end

	c.orig_fire = NewRaycastWeaponBase.fire
	function NewRaycastWeaponBase:fire(from_pos, direction, dmg_mul, shoot_player, spread_mul, autohit_mul, suppr_mul, target_unit)
		if c.active and not c.config.silent_ghost and c.unit and c.unit.dir and self._setup.user_unit and self._setup.user_unit == c.player_unit and not c:can_not_shoot() then
			return c.orig_fire(self, from_pos, c.unit.dir, c:hit_damage(c.unit_base, dmg_mul), shoot_player, c.config.weapon_spread, autohit_mul, suppr_mul, target_unit)
		end
		return c.orig_fire(self, from_pos, direction, dmg_mul, shoot_player, spread_mul, autohit_mul, suppr_mul, target_unit) 
	end

	c.orig_hit_accuracy = StatisticsManager.hit_accuracy
	function StatisticsManager:hit_accuracy(...)
		c.accuracy = c.config.freeze_accuracy and c.accuracy or c.orig_hit_accuracy(self, ...)
		return c.accuracy
	end

	c.orig_session_hit_accuracy = StatisticsManager.session_hit_accuracy
	function StatisticsManager:session_hit_accuracy(...)
		c.session_accuracy = c.config.freeze_accuracy and c.session_accuracy or c.orig_session_hit_accuracy(self, ...)
		return c.session_accuracy
	end

	local mvec1, fake_angle_timer, yaw_spin_speed, pitch_spin_speed, jitter_timer = Vector3(), 0, 1, 1, 0
	c.orig_set_rotation = PlayerCamera.set_rotation
	function PlayerCamera:set_rotation(rot)
		if _G.IS_VR or not c.active or (not c.config.inverted_look_direction and not c.config.angle_restriction and not c.config.spin_player and not c.config.fake_lag) then
			return c.orig_set_rotation(self, rot)
		end

		local new_rot = rot
		local sync_yaw = new_rot:yaw()
		local sync_pitch = new_rot:pitch()
		local dt = TimerManager:main():delta_time()

		mrotation.y(new_rot, mvec1)
		mvector3.multiply(mvec1, 100000)
		mvector3.add(mvec1, self._m_cam_pos)
		self._camera_controller:set_target(mvec1)
		mrotation.z(new_rot, mvec1)
		self._camera_controller:set_default_up(mvec1)
		mrotation.set_yaw_pitch_roll(self._m_cam_rot, sync_yaw, sync_pitch, new_rot:roll())
		mrotation.y(self._m_cam_rot, self._m_cam_fwd)
		mrotation.x(self._m_cam_rot, self._m_cam_right)

		-- Spin player
		if c.config.spin_player then
			sync_yaw = sync_yaw + yaw_spin_speed
			sync_pitch = sync_pitch + pitch_spin_speed

			if sync_yaw > 180 then -- sync_yaw stays within the range -180 to 180
				sync_yaw = sync_yaw - 360
			elseif sync_yaw < -180 then
				sync_yaw = sync_yaw + 360
			end

			if sync_pitch > 85 then
				sync_pitch = sync_pitch - 170
			elseif sync_pitch < -85 then
				sync_pitch = sync_pitch + 170
			end
			--sync_pitch = -85 -- -85 looks downward

			yaw_spin_speed = (yaw_spin_speed + 1) % 360 -- Adjust spin speed
			pitch_spin_speed = (pitch_spin_speed + 1) % 170
		end

		if c.config.inverted_look_direction then
			sync_yaw = sync_yaw % 360
			sync_pitch = sync_pitch % 170
			sync_yaw = sync_yaw < 0 and 360 - sync_yaw or sync_yaw
			sync_pitch = sync_pitch < 0 and 170 - sync_pitch or sync_pitch
		end

		if c.config.fake_lag then
			-- Fake angle
			fake_angle_timer = fake_angle_timer + dt
			if fake_angle_timer >= math.random(2,4) then
				sync_yaw = (sync_yaw + math.random(-90, 90)) % 360 -- Rotate player yaw by 90 degrees
				fake_angle_timer = 0
			end

			-- Jitter rotation
			jitter_timer = jitter_timer + dt  -- Increment the jitter timer by delta time
			if jitter_timer >= math.random(1, 2) then
				local jitter_amount = 5  -- Max jitter amount in degrees
				local jitter_yaw = math.random(-jitter_amount, jitter_amount)
				local jitter_pitch = math.random(-jitter_amount, jitter_amount)
				sync_yaw = (sync_yaw + jitter_yaw) % 360
				sync_pitch = (sync_pitch + jitter_pitch) % 170
				jitter_timer = 0
			end
		end

		-- Angle restriction
		if c.config.angle_restriction then
			local max_correction_angle = 45

			if sync_yaw > max_correction_angle then
				sync_yaw = max_correction_angle
			elseif sync_yaw < -max_correction_angle then
				sync_yaw = -max_correction_angle
			end
		end

		-- set network protocol range
		sync_pitch = math.clamp(sync_pitch, -85, 85) + 85

		if c.config.inverted_look_direction then
			sync_yaw = math.floor(255 * (360 - sync_yaw) / 360)
			sync_pitch = math.floor(127 * (170 - sync_pitch) / 170)
		else
			sync_yaw = math.floor(255 * sync_yaw / 360)
			sync_pitch = math.floor(127 * sync_pitch / 170)
		end

		if sync_yaw ~= self._sync_yaw or sync_pitch ~= self._sync_pitch then
			self._unit:network():send("set_look_dir", sync_yaw, sync_pitch)
			--managers.mission._fading_debug_output:script().log(tostring(sync_yaw) .. " - " .. tostring(sync_pitch), Color.red)
			self._sync_yaw = sync_yaw
			self._sync_pitch = sync_pitch
		end
	end
end
c:open_aimbot_config()