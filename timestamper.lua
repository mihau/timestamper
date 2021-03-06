bindings = {
    ["Ctrl-p"] = "print_time",
    }

function descriptor()
	return {
		title = "timestamper";
		version = "0.1";
		author = "mszymanski";
		url = '';
		description = [[
timestamper
]];
		capabilities = {"menu"}
	}
end

duration_limit = 0.0

events = {}
event_spans = {} -- stores spans
object_states = {} -- indicates if a particular event started or not
event_duration_sum = 0.0
osd_channel_id = nil
experiment_start_time = 0.0
filename_suffix = ""
config_dialog = nil

html_content = ""

-- globals for configuration
event_labels_str = ""
event_labels = {}

overall_duration_limit = 0.0
event_duration_limit = 0.0

button_functions = {}
-- TODO: finish compensation


function experiment_start()
    osd_channel_id = vlc.osd.channel_register()
    local input = vlc.object.input()
    local current_time = vlc.var.get(input, "time")
    experiment_start_time = current_time
    -- assuming that start event has id 0 and has no duration
    table.insert(event_spans, {experiment_start_time, experiment_start_time, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0})
    add_event_to_html(table.getn(event_spans), 0, experiment_start_time, experiment_start_time)
end

-- this function defines the format in which events are pute
-- function get_event_name()

function add_event_to_html(event_id, object_id, start_time, end_time)
    local element =  "#"..event_id..": object "..object_id.." | start: "..(start_time/1000000).." | end: "..(end_time/1000000)
    -- html_dialog:set_text(html_content)
    event_list_dialog:add_value(element)
end



function object_interaction(object_id)
    local input = vlc.object.input()
    local current_time = vlc.var.get(input, "time")
    vlc.msg.dbg("object "..object_id.." event at "..current_time)

    table.insert(events, {current_time, object_id})

    if not object_states[object_id] then
        object_states[object_id] = {}
        object_states[object_id]['duration_sum'] = 0.0
    end

    if object_states[object_id]["started"] then
        -- a span ended
        object_states[object_id]["started"] = false
        object_states[object_id]["end"] = current_time

        local start_time = object_states[object_id]["begin"]
        local end_time = current_time
        local duration = object_states[object_id]["end"] - object_states[object_id]["begin"]
        local relative_start_time = start_time - experiment_start_time
        local relative_end_time = end_time - experiment_start_time
        event_duration_sum = event_duration_sum + duration
        object_states[object_id]['duration_sum'] = object_states[object_id]['duration_sum'] + duration
        local object_duration_sum = object_states[object_id]['duration_sum']

        if event_duration_sum > duration_limit then
            duration_overflow = event_duration_sum - duration_limit
        else
            duration_overflow = 0.0
        end

        local compensated_duration = duration - duration_overflow
        local compensated_end_time = end_time - duration_overflow
        local compensated_relative_end_time = relative_end_time - duration_overflow
        local compensated_event_duration_sum = event_duration_sum - duration_overflow
        local compensated_object_duration_sum = object_duration_sum - duration_overflow



        -- this defines the columns in the csv
        local event_data = {
            start_time,
            end_time,
            relative_start_time,
            relative_end_time,
            duration,
            event_duration_sum,
            object_duration_sum,
            object_id,
            duration_overflow,
            compensated_duration,
            compensated_end_time,
            compensated_relative_end_time,
            compensated_event_duration_sum,
            compensated_object_duration_sum,
        }
        print(event_data)

        table.insert(event_spans, event_data)
        local event_id = table.getn(event_spans)
        add_event_to_html(event_id, object_id, start_time, end_time)
    else
        -- a span began
        object_states[object_id]["started"] = true
        object_states[object_id]["begin"] = current_time
    end

    if duration_limit > 0.0 then
        if event_duration_sum > duration_limit then
            print(osd_channel_id)
            local duration_limit_seconds = duration_limit / 1000000
            vlc.osd.message("reached duration limit of "..duration_limit_seconds.."s", osd_channel_id, "bottom-right")
        end
    end

end

function object_one_interaction()
    object_interaction(1)
end

function object_two_interaction()
    object_interaction(2)
end

function delete_events()
    -- local selected_events = event_list_dialog:get_selection()
    -- vlc.msg.dbg(table.getn(selected_events))
    -- for some reason last added element is always returned no matter what
    -- was selected
    for key, event in pairs(event_list_dialog:get_selection()) do
        local event_id = tonumber(string.match(event, "#(%d+): .*"))
        table.remove(event_spans, event_id)
    end
    event_list_dialog:clear()
    for key, event in pairs(event_spans) do
        add_event_to_html(key, event[8], event[1], event[2])
    end
end

function export_to_csv()
    print("registered "..table.getn(events).." events, total of "..event_duration_sum)
    local uri = vlc.strings.decode_uri(vlc.input.item():uri()) -- Format: file:///dir1/dir2/file.ext
    local filePath = string.gsub(uri, "file:///", "")          -- Format: dir1/dir2/file.ext
    filename_suffix = filename_suffix_input:get_text()
    local export_path = filePath..filename_suffix..".csv"
    io.output(export_path)
    io.write("start_time,end_time,relative_start_time,relative_end_time,duration,duration_sum,object_duration_sum,object_id,duration_overflow,compensated_duration,compensated_end_time,compensated_relative_end_time,compensated_event_duration_sum,compensated_object_duration_sum\n")
    for key, event in pairs(event_spans) do
        print(event[1]..","..event[2]..","..event[3]..","..event[4]..","..event[5]..","..event[6]..","..event[7]..","..event[8]..","..event[9]..","..event[10]..","..event[11]..","..event[12]..","..event[13]..","..event[14].."\n")
        io.write(event[1]..","..event[2]..","..event[3]..","..event[4]..","..event[5]..","..event[6]..","..event[7]..","..event[8]..","..event[9]..","..event[10]..","..event[11]..","..event[12]..","..event[13]..","..event[14].."\n")
    end
    io.close()
end
function partial(f, arg)
    return function()
        return f(arg)
    end
end

function dummy_button(n)
    vlc.msg.dbg(n)
end

function create_dialog()
    dialog = vlc.dialog("Timestamper")
    dialog:add_button("experiment start", experiment_start, 1, 1, 1, 1)
    dialog:add_button("export to csv", export_to_csv, 2, 1, 1, 1)
    dialog:add_label("Filename suffix", 1, 2, 1, 1)
    filename_suffix_input = dialog:add_text_input(filename_suffix, 2, 2, 1, 1)

    for i = 1,table.getn(event_labels),1
    do
        fun = partial(object_interaction, i)
        table.insert(button_functions, fun)
        dialog:add_button(i.." "..event_labels[i], fun, 3, i, 1, 1)
        vlc.msg.dbg(i)
    end
    -- dialog:add_button("object 1 event", object_one_interaction, 1, 3, 1, 1)
    -- dialog:add_button("object 2 event", object_two_interaction, 2, 3, 1, 1)
    -- -- html_dialog = dialog:add_html("", 1, 4, 1, 5)
    event_list_dialog = dialog:add_list({})
    -- dialog:add_button("delete selected events", delete_events, 2, 4, 1, 1)
end 

-- tools

function split(inputstr, sep)
        if sep == nil then
                sep = "%s"
        end
        local t={} ; i=1
        for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
                t[i] = str
                i = i + 1
        end
        return t
end

function serialize(t)
    local serializedValues = {}
    local value, serializedValue
    for i=1,#t do
        value = t[i]
        serializedValue = type(value)=='table' and serialize(value) or value
        table.insert(serializedValues, serializedValue)
    end
    return string.format("{ %s }", table.concat(serializedValues, ', ') )
end
-- end tools

-- begin configuration
function apply_configuration()
    event_labels_str = event_labels_input:get_text()
    overall_duration_limit = tonumber(overall_duration_limit_input:get_text())
    event_duration_limit = tonumber(event_duration_limit_input:get_text())

    duration_limit = event_duration_limit * 1000000

    event_labels = split(event_labels_str, ",") 
    vlc.msg.dbg(serialize(event_labels))
    vlc.msg.dbg(overall_duration_limit)
    vlc.msg.dbg(event_duration_limit)

    
    config_dialog:delete()
    create_dialog()
end

function create_config_dialog()
    config_dialog = vlc.dialog("Timestamper configuration")

    config_dialog:add_label("event labels (comma separated)", 1, 1, 1, 1)
    event_labels_input = config_dialog:add_text_input(event_labels_str, 2, 1, 1, 1)

    config_dialog:add_label("overall duration limit (seconds)", 1, 2, 1, 1)
    overall_duration_limit_input = config_dialog:add_text_input(overall_duration_limit, 2, 2, 1, 1)

    config_dialog:add_label("event duration limit (seconds)", 1, 3, 1, 1)
    event_duration_limit_input = config_dialog:add_text_input(event_duration_limit, 2, 3, 1, 1)

    config_dialog:add_button("Apply", apply_configuration, 3, 1, 1, 1)
end
-- end configuration


function key_press( var, old, new, data )
    local key = new
    print("key_press:",tostring(key))
    if bindings[key] then
        print_time()
    else
        vlc.msg.err("Key `"..key.."' isn't bound to any action.")
    end
end


function activate()
    vlc.msg.dbg("timestamper starts")
    create_config_dialog()
end

function deactivate()
end

function close()
	vlc.deactivate()
end

function meta_changed()
end

function menu()
	return {"Control panel", "Settings"}
end
function trigger_menu(id)
	if id==1 then -- Control panel
		if dlg then dlg:delete() end
		create_dialog()
	elseif id==2 then -- Settings
		if dlg then dlg:delete() end
		create_dialog_S()
	end
end
