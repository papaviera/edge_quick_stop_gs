local ffi = require "ffi"
local vector = require "vector";

local trace = require "gamesense/trace";
local csgo_weapons = require "gamesense/csgo_weapons";

local new_class = function()
    local mt, mt_data, this_mt = { }, { }

    mt.__metatable = false
    mt_data.struct = function(self, name)
        assert(type(name) == 'string', 'invalid class name')
        assert(rawget(self, name) == nil, 'cannot overwrite subclass')

        return function(data)
            assert(type(data) == 'table', 'invalid class data')
            rawset(self, name, setmetatable(data, {
                __metatable = false,
                __index = function(self, key)
                    return
                        rawget(mt, key) or
                        rawget(this_mt, key)
                end
            }))

            return this_mt
        end
    end

    this_mt = setmetatable(mt_data, mt)

    return this_mt
end

local edge_quick_stop = ui.new_hotkey("MISC", "Movement", "Edge quick stop");

local ctx = new_class()
:struct "edge_quick_stop" {
	last_move_buttons = 0,
	last_pressed = 0,

	LADDER_EDGE_GRAB_HEIGHT_DELTA = 6,
	LADDER_EDGE_GRAB_DISTACE = 24,

	masks = {
		MASK_PLAYERSOLID_BRUSHONLY = 81931,
		MASK_SOLID_BRUSHONLY = 16395,
		MASK_SHOT_PORTAL = 33570819,
		MASK_SHOT_HULL = 100679691,
		MASK_SHOT_BRUSHONLY = 67125251,
		MASK_WEAPONCLIPPING = 100679683,
		MASK_FLOORTRACE = 67125251,
		MASK_SHOT = 1174421507,
		MASK_VISIBLE_AND_NPCS = 33579137,
		MASK_VISIBLE = 24705,
		MASK_BLOCKLOS_AND_NPCS = 33570881,
		MASK_BLOCKLOS = 16449,
		MASK_OPAQUE_AND_NPCS = 33570945,
		MASK_OPAQUE = 16513,
		MASK_WATER = 16432,
		MASK_NPCFLUID = 33701891,
		MASK_NPCSOLID = 33701899,
		MASK_PLAYERSOLID = 33636363,
		MASK_SOLID = 33570827,
		MASK_ALL = 4294967295,
		CONTENTS_HITBOX = 1073741824,
		CONTENTS_LADDER = 536870912,
		CONTENTS_TRANSLUCENT = 268435456,
		CONTENTS_DETAIL = 134217728,
		CONTENTS_DEBRIS = 67108864,
		CONTENTS_MONSTER = 33554432,
		CONTENTS_ORIGIN = 16777216,
		CONTENTS_UNUSED5 = 8388608,
		CONTENTS_UNUSED4 = 4194304,
		CONTENTS_UNUSED3 = 2097152,
		CONTENTS_UNUSED2 = 1048576,
		CONTENTS_GRENADECLIP = 524288,
		CONTENTS_BRUSH_PAINT = 262144,
		CONTENTS_MONSTERCLIP = 131072,
		CONTENTS_PLAYERCLIP = 65536,
		CONTENTS_AREAPORTAL = 32768,
		CONTENTS_MOVEABLE = 16384,
		CONTENTS_IGNORE_NODRAW_OPAQUE = 8192,
		CONTENTS_TEAM2 = 4096,
		CONTENTS_TEAM1 = 2048,
		CONTENTS_BLOCKLIGHT = 1024,
		CONTENTS_UNUSED = 512,
		CONTENTS_TESTFOGVOLUME = 256,
		CONTENTS_CURRENT_90 = 0x80000,
		ALL_VISIBLE_CONTENTS = 255,
		LAST_VISIBLE_CONTENTS = 128,
		CONTENTS_OPAQUE = 128,
		CONTENTS_BLOCKLOS = 64,
		CONTENTS_WATER = 32,
		CONTENTS_SLIME = 16,
		CONTENTS_GRATE = 8,
		CONTENTS_AUX = 4,
		CONTENTS_WINDOW = 2,
		CONTENTS_SOLID = 1,
		CONTENTS_EMPTY = 0,
		MASK_DEADSOLID = 65547,
		MASK_SPLITAREAPORTAL = 48,
		MASK_NPCWORLDSTATIC_FLUID = 131075,
		MASK_NPCWORLDSTATIC = 131083,
		MASK_NPCSOLID_BRUSHONLY = 147467
	},

    input = ffi.cast("void**", ffi.cast("char*", client.find_signature("client.dll", "\xB9\xCC\xCC\xCC\xCC\x8B\x40\x38\xFF\xD0\x84\xC0\x0F\x85")) + 1)[0],	
	get_usercmd = vtable_thunk(8, "void*(__thiscall*)(void*,int, int)"),


	init = function(self)
		local linker = function(cmd)
			self:createmove(cmd)
		end

		client.set_event_callback("setup_command", linker);
	end,
    
    get_buttons = function(self, cmd)
		local buttons = ffi.cast("int*", ffi.cast("char*", self.get_usercmd(self.input, 0, cmd.command_number)) + 48)
		return buttons;
	end,

    simulate_movement = function(self, me, origin, flags, velocity)
        local mins = vector(entity.get_prop(me, "m_vecMins"))
        local maxs = vector(entity.get_prop(me, "m_vecMaxs"))

        origin = origin or vector(entity.get_origin(me));
        velocity = velocity or vector(entity.get_prop(me, "m_vecVelocity"));
        flags = flags or entity.get_prop(me, "m_fFlags");

        local ti = globals.tickinterval();
        local on_ground = bit.band(flags, 1) == 1;

        if not on_ground then
            velocity.z = velocity.z - 800 * ti;
        end

        if on_ground then
            local speed = velocity:length();
            if speed > 0 then
                local drop = speed * 4 * ti;
                local newspeed = math.max(speed - drop, 0);
                velocity = velocity * (newspeed / speed);
            end
        end

        local src = origin;
        local end_pos = src + (velocity * ti);

        local tr = trace.hull(src, end_pos, mins, maxs, {
            skip = me,
            mask = "CONTENTS_SOLID"
        });

        if tr.fraction ~= 1 then
            for i = 0, 2 do
                local dot = velocity:dot(tr.plane.normal);
                if dot < 0 then
                    velocity = velocity - tr.plane.normal * dot;
                end

                end_pos = tr.end_pos + (velocity * (ti * (1 - tr.fraction)));

                tr = trace.hull(tr.end_pos, end_pos, mins, maxs, {
                    skip = me,
                    mask = "CONTENTS_SOLID"
                })

                if tr.fraction == 1 then break end
            end
        end

        origin = tr.end_pos;

        local gtr = trace.hull(origin, vector(origin.x, origin.y, origin.z - 2), mins, maxs, {
            skip = me,
            mask = "CONTENTS_SOLID"
        })

        if gtr.fraction ~= 1 and gtr.plane.normal.z > 0.7 then
            flags = bit.bor(flags, 1)
        else
            flags = bit.band(flags, bit.bnot(1))
        end

        return origin, flags, velocity;
    end,

	catch_cliff = function(self, ent, ticks_needed)
        local origin, flags, velocity = self:simulate_movement(ent);

        for i = 1, ticks_needed do
            origin, flags, velocity = self:simulate_movement(ent, origin, flags, velocity);
        end


		local mins = vector(entity.get_prop(ent, "m_vecMins"));
		local maxs = vector(entity.get_prop(ent, "m_vecMaxs"));

		local start_pos = origin:clone();
		start_pos.z = start_pos.z - self.LADDER_EDGE_GRAB_HEIGHT_DELTA;

		local end_pos = origin - velocity:normalized() * self.LADDER_EDGE_GRAB_DISTACE;

		local trace = trace.hull(start_pos, end_pos, mins, maxs, {
            skip = me,
            mask = bit.band(self.masks.MASK_PLAYERSOLID, bit.bnot(self.masks.CONTENTS_PLAYERCLIP))
        })
	
		if ( trace.fraction ~= 1.0 and bit.band(trace.contents, self.masks.CONTENTS_LADDER) ~= 0 and trace.plane.normal.z ~= 1.0 ) then
    	    return true;
    	end

		return false;
	end,

	createmove = function(self, cmd)
        if not ui.get(edge_quick_stop) then
            return
        end

		local me = entity.get_local_player()

		if me == nil then
			return
		end

		local weapon = entity.get_player_weapon(me);

		if weapon == nil then
			return
		end

        local BUTTONS = self:get_buttons(cmd)

		if BUTTONS == nil then
			return
		end

        local wpn = csgo_weapons(weapon);

		local surface_friction = entity.get_prop(me, "m_surfaceFriction");
		local flags = entity.get_prop(me, "m_fFlags");

		if bit.band(flags, 1) ~= 1 then
			return
		end

		local velocity = vector(entity.get_prop(me, "m_vecVelocity"));
		local speed = velocity:length2d();

		local move_type = entity.get_prop(me, "m_MoveType");

		if move_type == 9 or move_type == 8 then
			return
		end

		local sv_friction = cvar.sv_friction:get_float();
		local sv_stopspeed = cvar.sv_stopspeed:get_float();
		local ticks_needed = math.max( 2, math.ceil( speed / ( sv_friction * surface_friction * math.max( speed, sv_stopspeed ) * globals.tickinterval() ) ) );

		if self:catch_cliff(me, ticks_needed + 5) then
			--return
		end

		local origin = vector(entity.get_prop(me, "m_vecAbsOrigin"));

		local mins = vector(entity.get_prop(me, "m_vecMins"));
		local maxs = vector(entity.get_prop(me, "m_vecMaxs"));

		local IN_FORWARD   = 0x8    -- 8
		local IN_BACK      = 0x10   -- 16
		local IN_MOVELEFT  = 0x200  -- 512
		local IN_MOVERIGHT = 0x400  -- 1024

		local sv_standable_normal = cvar.sv_standable_normal:get_float();

		local function check_edge(ticks_ahead)
			local origin, flags, velocity = self:simulate_movement(me);
            
			for i = 1, ticks_ahead do
				origin, flags, velocity = self:simulate_movement(me, origin, flags, velocity)
			end

            local start = origin + vector(0, 0, 2);
            local end_pos = origin - vector(0, 0, 4);
            local tr = trace.hull(start, end_pos, mins, maxs, {
                skip = me,
                mask = bit.band(self.masks.MASK_PLAYERSOLID, bit.bnot(self.masks.CONTENTS_PLAYERCLIP))
            })

            return tr.fraction >= 1.0 or tr.plane.normal.z < sv_standable_normal or velocity.z < 0;
		end

		local at_edge = check_edge(3);

		local approaching_edge = false;

		if not at_edge and speed > 1 then

			for i = 1, ticks_needed do
				if check_edge(i) then
					approaching_edge = true;
					break;
				end
			end
		end

		if not at_edge and not approaching_edge then
			return
		end

		local view_yaw = cmd.yaw;
		local view_yaw_rad = view_yaw * (math.pi / 180)
		local max_weapon_speed = wpn.max_player_speed;

		if at_edge then
			local forwardmove = cmd.forwardmove / 450;
			local leftmove = cmd.sidemove / 450;

			local wish_x = math.cos( view_yaw_rad ) * forwardmove - math.sin( view_yaw_rad ) * leftmove;
			local wish_y = math.sin( view_yaw_rad ) * forwardmove + math.cos( view_yaw_rad ) * leftmove;
			local wish_len = math.sqrt( wish_x * wish_x + wish_y * wish_y );

			if wish_len > .001 then
				local wish_norm_x = wish_x / wish_len;
				local wish_norm_y = wish_y / wish_len;

				local test_origin = origin;
				test_origin.x = test_origin.x + wish_norm_x * 4.0;
				test_origin.y = test_origin.y + wish_norm_y * 4.0;

				local start = vector( test_origin.x, test_origin.y, origin.z + 2.0 );
				local end_pos = vector ( test_origin.x, test_origin.y, origin.z - 4.0 );

				local result = trace.hull(start, end_pos, mins, maxs, {
                    skip = me,
                    mask = bit.band(self.masks.MASK_PLAYERSOLID, bit.bnot(self.masks.CONTENTS_PLAYERCLIP))
                })
                
				local input_toward_edge = result.fraction >= 1 or result.plane.normal.z < sv_standable_normal;

				if input_toward_edge then
					local pushback_yaw = math.atan2( wish_norm_y, wish_norm_x ) * ( 180.0 / math.pi ) + 180.0;
					local pushback_rotation = ( view_yaw - pushback_yaw ) * ( math.pi / 180.0 );

					cmd.forwardmove = ( math.clamp( math.cos( pushback_rotation ) * 0.3, -1.0, 1.0 ) ) * 450;
					cmd.sidemove = ( math.clamp( math.sin( pushback_rotation ) * -0.3, -1.0, 1.0 ) ) * 450;


					local buttons = BUTTONS[0];
					buttons = bit.band(BUTTONS[0], bit.bnot(bit.bor(IN_FORWARD, IN_BACK, IN_MOVELEFT, IN_MOVERIGHT)))

					if cmd.forwardmove > 0.0 then
					    buttons = bit.bor(buttons, 0x8)      -- IN_FORWARD
					elseif cmd.forwardmove < 0.0 then
					    buttons = bit.bor(buttons, 0x10)     -- IN_BACK
					end

					if cmd.sidemove > 0.0 then
					    buttons = bit.bor(buttons, 0x200)    -- IN_MOVELEFT
					elseif cmd.sidemove < 0.0 then
					    buttons = bit.bor(buttons, 0x400)    -- IN_MOVERIGHT
					end

					BUTTONS[0] = buttons

					if speed <= 5.0 then
					    return
					end
				end
			end

			if speed > 1 then
				local stop_yaw = math.atan2(velocity.y, velocity.x) * ( 180 / math.pi ) + 180;
				local rotation = (view_yaw - stop_yaw) * ( math.pi / 180 );

				local sv_accelerate = cvar.sv_accelerate:get_float();
				local accel_speed = sv_accelerate * max_weapon_speed * surface_friction * globals.tickinterval();
				local move_speed = (speed < accel_speed) and speed or max_weapon_speed;

				local fwd = math.clamp(move_speed / max_weapon_speed, 0, 1);

				cmd.forwardmove = ( math.clamp( math.cos( rotation ) * fwd, -1.0, 1.0 ) ) * 450;
				cmd.sidemove = ( math.clamp( math.sin( rotation ) * fwd * -1.0, -1.0, 1.0 ) ) * 450;

				local buttons = BUTTONS[0]
				buttons = bit.band(buttons, bit.bnot(bit.bor(IN_FORWARD, IN_BACK, IN_MOVELEFT, IN_MOVERIGHT)))

				if cmd.forwardmove > 0.0 then
				    buttons = bit.bor(buttons, IN_FORWARD)
				elseif cmd.forwardmove < 0.0 then
				    buttons = bit.bor(buttons, IN_BACK)
				end

				if cmd.sidemove > 0.0 then
				    buttons = bit.bor(buttons, IN_MOVELEFT)
				elseif cmd.sidemove < 0.0 then
				    buttons = bit.bor(buttons, IN_MOVERIGHT)
				end

				BUTTONS[0] = buttons
			end
			return;
		end


		local stop_yaw = math.atan2(velocity.y, velocity.x) * (180.0 / math.pi) + 180.0
		local rotation = (view_yaw - stop_yaw) * (math.pi / 180.0)

		local sv_accelerate = cvar.sv_accelerate:get_float()
		local accel_speed = sv_accelerate * max_weapon_speed * surface_friction * globals.tickinterval()
		local move_speed = (speed < accel_speed) and speed or max_weapon_speed

		local fwd = math.clamp(move_speed / max_weapon_speed, 0.0, 1.0)

		cmd.forwardmove = (math.clamp(math.cos(rotation) * fwd, -1.0, 1.0)) * 450;
		cmd.sidemove = (math.clamp(math.sin(rotation) * fwd * -1.0, -1.0, 1.0)) * 450;

		local buttons = BUTTONS[0]

		buttons = bit.band(buttons, bit.bnot(bit.bor(IN_FORWARD, IN_BACK, IN_MOVELEFT, IN_MOVERIGHT)))

		if cmd.forwardmove > 0.0 then
		    buttons = bit.bor(buttons, IN_FORWARD)
		elseif cmd.forwardmove < 0.0 then
		    buttons = bit.bor(buttons, IN_BACK)
		end

		if cmd.sidemove > 0.0 then
		    buttons = bit.bor(buttons, IN_MOVELEFT)
		elseif cmd.sidemove < 0.0 then
		    buttons = bit.bor(buttons, IN_MOVERIGHT)
		end

		BUTTONS[0] = buttons
	end
}
ctx.edge_quick_stop:init();
