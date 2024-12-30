-- teleporter_plates/init.lua

local modname = minetest.get_current_modname()

--------------------------------------------------------------------------
-- 0) Mod Storage + Global table
--------------------------------------------------------------------------

-- 0a) Get reference to this mod’s storage
local mod_storage = minetest.get_mod_storage()

-- 0b) Global ephemeral storage for all networks (read from mod_storage if possible)
teleporter_plates = teleporter_plates or {}
teleporter_plates.networks = teleporter_plates.networks or {}

-- 0c) Try to load previously saved networks from JSON
local stored_json = mod_storage:get_string("networks")
if stored_json and stored_json ~= "" then
    local parsed = minetest.parse_json(stored_json)
    if parsed then
        teleporter_plates.networks = parsed
    end
end

-- 0d) Helper function to save networks to mod_storage
local function save_networks()
    local data_str = minetest.write_json(teleporter_plates.networks)
    mod_storage:set_string("networks", data_str)
end

--------------------------------------------------------------------------
-- 0e) Get or create a list for a given network name
--------------------------------------------------------------------------
local function get_network_destinations(netname)
    if not teleporter_plates.networks[netname] then
        teleporter_plates.networks[netname] = {}
    end
    return teleporter_plates.networks[netname]
end

--------------------------------------------------------------------------
-- 1) Build the textlist items string
--------------------------------------------------------------------------
local function build_textlist(dest_table)
    local items = {}
    for _, dest in ipairs(dest_table) do
        -- Show only the destination name
        local label = dest.name
        table.insert(items, label)
    end
    return table.concat(items, ",")
end

--------------------------------------------------------------------------
-- 2) Show the formspec
--------------------------------------------------------------------------
local function show_network_formspec(player, pos)
    if not player then return end

    local pname    = player:get_player_name()
    local meta     = minetest.get_meta(pos)
    local network  = meta:get_string("network_name")
    if network == "" then
        network = "default"
    end

    local selected = meta:get_int("selected_index")
    local editing  = meta:get_int("editing_index")
    local list     = get_network_destinations(network)

    -- Validate
    if selected < 1 or selected > #list then
        selected = 0
    end
    if editing < 1 or editing > #list then
        editing = 0
    end

    -- If editing, populate fields
    local def_name, def_x, def_y, def_z = "", "", "", ""
    if editing > 0 then
        local e = list[editing]
        if e then
            def_name = e.name or ""
            def_x    = tostring(e.x or "")
            def_y    = tostring(e.y or "")
            def_z    = tostring(e.z or "")
        end
    end

    
    local textlist_str = build_textlist(list)
    local formname     = "teleporter_plates:netplate_form_"..pos.x.."_"..pos.y.."_"..pos.z

    local fs = ([[
        size[12,9.5]

        label[0.2,0.2;VoxeLibre Teleporter]
        button_exit[10.9,8.76;1,0.8;close;Close]

        label[9,0.09;Network:]
        field[10.2,0.2;2,0.8;net_name;;%s]
        button[9.9,0.7;2.0,0.9;set_net;Set Network]

        label[0.3,1.1;Destinations in Network:]
        textlist[0.3,1.6;6,5;dlist;%s;%d;true]

        button[0.3,7.1;2,0.9;teleport_sel;Teleport]
        button[2.4,7.1;1.8,0.9;edit_sel;Edit]
        button[4.3,7.1;2,0.9;delete_sel;Delete]

        label[6.7,1.0;Add / Update Destination:]
        field[7.0,2.0;3,0.8;dest_name;Name;%s]
        field[7.0,3.0;2,0.8;dest_x;X;%s]
        field[7.0,4.0;2,0.8;dest_y;Z;%s]
        field[7.0,5.0;2,0.8;dest_z;Y;%s]
        button[6.7,5.7;3,0.9;add_update;Add / Update]

        label[0.1,8.0;Manual Teleport (not saved):]
        field[0.3,9.0;2,0.8;man_x;X;]
        field[2.4,9.0;2,0.8;man_y;Z;]
        field[4.5,9.0;2,0.8;man_z;Y;]
        button[6.5,8.62;2,1;man_teleport;Teleport]
    ]]):format(
        network, textlist_str, selected,
        def_name, def_x, def_y, def_z
    )

    minetest.show_formspec(pname, formname, fs)
end

--------------------------------------------------------------------------
-- 3) Register the node
--------------------------------------------------------------------------
minetest.register_node(modname..":net_plate", {
    description = "Network Teleporter Plate",
    tiles = {"mcl_end_crystal_item.png"},  -- Example texture
    drawtype = "nodebox",
    paramtype = "light",
    light_source = 14,
    sunlight_propagates = true,
    node_box = {
        type = "fixed",
        fixed = {{-0.5, -0.5, -0.5, 0.5, -0.45, 0.5}},
    },
    selection_box = {
        type = "fixed",
        fixed = {{-0.5, -0.5, -0.5, 0.5, -0.45, 0.5}},
    },
    collision_box = {
        type = "fixed",
        fixed = {{-0.5, -0.5, -0.5, 0.5, -0.45, 0.5}},
    },
    groups = {cracky=3, stone=1, pick=1},

    on_rightclick = function(pos, node, clicker, itemstack, pointed_thing)
        show_network_formspec(clicker, pos)
    end,
})

--------------------------------------------------------------------------
-- 4) Handle all formspec events
--------------------------------------------------------------------------
minetest.register_on_player_receive_fields(function(player, formname, fields)
    -- We only care about forms named like "teleporter_plates:netplate_form_x_y_z"
    local prefix = "teleporter_plates:netplate_form_"
    if formname:sub(1, #prefix) ~= prefix then
        return
    end

    if not player then return end

    local pname  = player:get_player_name()
    local coords = formname:sub(#prefix+1)
    local x, y, z = coords:match("^(%-?%d+)_(%-?%d+)_(%-?%d+)$")
    if not (x and y and z) then return end

    local pos  = {x=tonumber(x), y=tonumber(y), z=tonumber(z)}
    local meta = minetest.get_meta(pos)
    if not meta then return end

    local network_name = meta:get_string("network_name")
    if network_name == "" then
        network_name = "default"
    end

    local list    = get_network_destinations(network_name)
    local sel_idx = meta:get_int("selected_index")
    local edt_idx = meta:get_int("editing_index")

    ------------------------------------------------------------------
    -- (A) Set Network
    ------------------------------------------------------------------
    if fields.set_net and fields.net_name then
        local newnet = fields.net_name
        if newnet == "" then
            newnet = "default"
        end
        meta:set_string("network_name", newnet)
        meta:set_int("selected_index", 0)
        meta:set_int("editing_index", 0)

        -- Save the updated networks table
        save_networks()

        minetest.after(0, function()
            show_network_formspec(player, pos)
        end)
        return
    end

    ------------------------------------------------------------------
    -- (B) Textlist selection
    ------------------------------------------------------------------
    if fields.dlist then
        local event = fields.dlist  -- Example: "CHG:2"
        local etype, idx_str = event:match("^(%u+):(%d+)$")
        if idx_str then
            local idx = tonumber(idx_str)
            if idx and idx >= 1 and idx <= #list then
                meta:set_int("selected_index", idx)
            else
                meta:set_int("selected_index", 0)
            end
        end
        minetest.after(0, function()
            show_network_formspec(player, pos)
        end)
        return
    end

    ------------------------------------------------------------------
    -- (C) Teleport to Selected
    ------------------------------------------------------------------
    if fields.teleport_sel then
        local sidx = meta:get_int("selected_index")
        local entry = list[sidx]
        if entry then
            player:set_pos({x=entry.x, y=entry.y, z=entry.z})
            minetest.chat_send_player(pname,
                ("Teleported to '%s' (%s, %s, %s)"):format(entry.name, entry.x, entry.y, entry.z)
            )
        else
            minetest.chat_send_player(pname, "No valid destination selected!")
        end
        minetest.close_formspec(pname, formname)
        return
    end

    ------------------------------------------------------------------
    -- (D) Edit Selected
    ------------------------------------------------------------------
    if fields.edit_sel then
        local sidx = meta:get_int("selected_index")
        if sidx >= 1 and sidx <= #list then
            meta:set_int("editing_index", sidx)
        else
            minetest.chat_send_player(pname, "No valid destination selected!")
        end
        minetest.after(0, function()
            show_network_formspec(player, pos)
        end)
        return
    end

    ------------------------------------------------------------------
    -- (E) Delete Selected
    ------------------------------------------------------------------
    if fields.delete_sel then
        local sidx = meta:get_int("selected_index")
        if sidx >= 1 and sidx <= #list then
            local removed = table.remove(list, sidx)
            if removed then
                minetest.chat_send_player(pname, "Deleted '"..removed.name.."'")
            end
            -- Reset selection & editing
            meta:set_int("selected_index", 0)
            meta:set_int("editing_index", 0)

            -- Save changes
            save_networks()
        else
            minetest.chat_send_player(pname, "No valid destination selected!")
        end
        minetest.after(0, function()
            show_network_formspec(player, pos)
        end)
        return
    end

    ------------------------------------------------------------------
    -- (F) Add / Update Destination
    ------------------------------------------------------------------
    if fields.add_update then
        local dname = fields.dest_name or ""
        local dx    = tonumber(fields.dest_x)
        local dy    = tonumber(fields.dest_y)
        local dz    = tonumber(fields.dest_z)

    if not (dx and dy and dz) then
     	minetest.chat_send_player(pname, "Coordinates must be numbers!")
    	return
    end

-- Additional checks
    if dx < -1000 or dx > 1000 or dy < 1 or dy > 30000 or dz < -1000 or dz > 1000 then
    	minetest.chat_send_player(pname, "Coordinates are out of acceptable range!")
    	return
    end

        if dname == "" or not dx or not dy or not dz then
            minetest.chat_send_player(pname, "Invalid name or coordinates!")
        else
            local eidx = meta:get_int("editing_index")
            if eidx >= 1 and eidx <= #list then
                -- Update existing entry
                local entry = list[eidx]
                entry.name = dname
                entry.x    = dx
                entry.y    = dy
                entry.z    = dz
                minetest.chat_send_player(pname,
                    ("Updated entry #%d to '%s'"):format(eidx, dname)
                )
                -- Auto-select updated entry
                meta:set_int("selected_index", eidx)
            else
                -- Add new
                table.insert(list, {
                    name = dname,
                    x    = dx,
                    y    = dy,
                    z    = dz,
                })
                local new_idx = #list
                meta:set_int("selected_index", new_idx)
                minetest.chat_send_player(pname, ("Added new entry '%s'"):format(dname))
            end

            -- Save changes
            save_networks()
        end

        -- Clear editing
        meta:set_int("editing_index", 0)

        minetest.after(0, function()
            show_network_formspec(player, pos)
        end)
        return
    end

    ------------------------------------------------------------------
    -- (G) Manual Teleport (not saved)
    ------------------------------------------------------------------
    if fields.man_teleport then
        local mx = tonumber(fields.man_x)
        local my = tonumber(fields.man_y)
        local mz = tonumber(fields.man_z)
        if mx and my and mz then
            player:set_pos({x=mx, y=my, z=mz})
            minetest.chat_send_player(pname,
                ("Teleported to (%d, %d, %d)"):format(mx, my, mz)
            )
        else
            minetest.chat_send_player(pname, "Invalid manual coordinates!")
        end
        minetest.close_formspec(pname, formname)
        return
    end
end)

------------------------------------------------------------
--RECIPE
--5) Register Crafting Recipe for Teleporter Plate
------------------------------------------------------------

minetest.register_craft({
    output = "teleporter_plates:net_plate",
    recipe = {
        {"mcl_core:glass",           "",          "mcl_core:glass"},
        {"",                   "mcl_ocean:sea_lantern", ""},
        {"mcl_core:glass",           "",          "mcl_core:glass"},
    },
    description = "Network Teleporter Plate",
    group = {teleporter_plate = 1},
})
