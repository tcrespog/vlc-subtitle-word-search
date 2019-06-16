--[[
Program: Subtitle Word Search
Purpose: Search words from the current subtitle file in a search engine 
Author: Tomás Crespo
License: GNU GENERAL PUBLIC LICENSE
]]

function descriptor()
    return {
        title = "Subtitle Word Search",
        version = "1.2",
        author = "Tomás Crespo",
        url = "https://github.com/tcrespog/vlc-subtitle-word-search",
        shortdesc = "Subtitle Word Search",
        description = "Search words from the current subtitle in a search engine",
        capabilities = {}
    }
end

-- Add your favourite search engines here, just add another entry of the type {name = "<Your name>", url = "<Your URL>"}
-- Make sure that the search engine has the %s text in the place of the text to search
search_engines = {
    { name = "Wikitionary", url = "http://en.wiktionary.org/wiki/%s" },
    { name = "WordReference EN-ES", url = "http://www.wordreference.com/enes/%s" },
    { name = "Wikipedia", url = "https://en.wikipedia.org/wiki/%s" },
    { name = "Urban Dictionary", url = "http://www.urbandictionary.com/define.php?term=%s" }
}

------- Subtitle navigation -------

-- Array containing the start and finish positions of each appearance time in the subtitle file text
historic_appearance_times = nil
-- The current index in the historial of apperance times
current_historic_apperance_time = nil

-- The current subtitle file full text
text = nil

-- Array containing the paths to the discovered subtitle files corresponding to the current video
subtitle_files_paths = nil

-- The current playing time timestamp
current_timestamp = nil

------- GUI elements -------
dlg = nil
dropdown_search_engines = nil
list_words = nil
text_box_html = nil
timestamp_label = nil
dropdown_subtitle_files = nil

function activate()
    draw_dialog()
end

function draw_dialog()
    dlg = vlc.dialog("Subtitle Word Search")

    dlg:add_label("<h2>Subtitles file</h2>", 1, 1)
    dropdown_subtitle_files = dlg:add_dropdown(1, 2)
    dlg:add_button("Load", process_subtitle_file_loading, 2, 2)

    dlg:add_label("<h2>Subtitle words</h2>", 1, 3)

    dlg:add_button("Refresh", process_words_capture, 1, 4)
    dlg:add_button("<<", navigate_backward, 2, 4)
    timestamp_label = dlg:add_label("00:00:00", 3, 4)
    dlg:add_button(">>", navigate_forward, 4, 4)
    dlg:add_button("Go", go_to_subtitle_time, 5, 4)

    list_words = dlg:add_list(1, 5, 5, 1)

    dlg:add_label("<h2>Word Search</h2>", 1, 6)
    dropdown_search_engines = dlg:add_dropdown(1, 7)
    dlg:add_button("Search", process_word_search, 2, 7)

    text_box_html = dlg:add_html("", 1, 8, 85, 10)

    discover_subtitle_file_paths()
    inject_subtitle_files()
    inject_search_engines()
    process_subtitle_file_loading()

    dlg:show()
end

--- Injects the search engine names in the corresponding dropdown widget
function inject_search_engines()
    for id, search_engine in ipairs(search_engines) do
        dropdown_search_engines:add_value(search_engine.name, id)
    end
end

--- Shows the splitted subtitle in the GUI along with the time at which it appears
-- @param subtitle {string} The subtitle to show
-- @param appearance_time_interval_limits {table} The index in the text corresponding to te first and last characters of an appearance time interval mark
function show_subtitle_and_time(subtitle, appearance_time_interval_limits)
    local appearance_time_interval = text:sub(appearance_time_interval_limits.start_index, appearance_time_interval_limits.finish_index)
    local timestamps = extract_timestamps(appearance_time_interval)

    draw_subtitle_words(subtitle)
    draw_subtitle_timestamp(timestamps.start)
end

--- Shows the splitted words from a subtitle in the list widget
-- @param subtitle {string} the subtitle to show
function draw_subtitle_words(subtitle)
    list_words:clear()

    local words = split_words(subtitle)
    for index, word in ipairs(words) do
        list_words:add_value(word, index)
    end
end

--- Draws a timestamp in the specific label
-- @param timestamp {string} The timestamp in hh:mm:ss,SSS format
function draw_subtitle_timestamp(timestamp)
    -- Store the current timestamp
    current_timestamp = timestamp

    local processed_timestamp = timestamp:match("%d+:%d+:%d+")
    timestamp_label:set_text(processed_timestamp)
end

--- Reads the timestamp placed at the corresponding button and visits that time in the video
function go_to_subtitle_time()
    local location_time_microseconds = convert_timestamp_to_time(current_timestamp) * 1000000

    vlc.var.set(vlc.object.input(), "time", location_time_microseconds)
end

--- Draws the subtitle files in the corresponding dropdown widget
function inject_subtitle_files()
    local directory_path = get_video_file_location()

    for id, subtitle_filepath in ipairs(subtitle_files_paths) do
        local start_index, finish_index = subtitle_filepath:find(directory_path, 1, true)
        local subtitle_filename = subtitle_filepath:sub(finish_index + 1) -- Ex. video.srt, video.eng.srt, ...

        dropdown_subtitle_files:add_value(subtitle_filename, id)
    end
end

-- Does all the required actions to load the text of a subtitle file in memory.
-- Then show the current time's subtitle words or displays error messages if something went wrong
function process_subtitle_file_loading()
    local selected_path = get_selected_subtitle_file()

    if (selected_path) then
        local error_message = load_subtitle_file_text(selected_path)

        if (error_message) then
            text_box_html:set_text(generate_html_error(error_message))
        else
            process_words_capture()
        end
    else
        local video_directory, video_filename = get_video_file_location()
        text_box_html:set_text(generate_html_error("No subtitle files found at " .. video_directory .. " for the file " .. video_filename))
    end
end

--- Does all the required actions to show the words of the currently selected subtitle in the corresponding list widget.
-- Shows a red-colored error message in the query box if something goes wrong
function process_words_capture()
    -- There is a subtitle text loaded in memory
    if (text) then
        local current_playing_time = get_current_time()
        local subtitle = search_corresponding_subtitle_at_time(current_playing_time)

        if (subtitle) then
            draw_subtitle_words(subtitle)
        else
            draw_subtitle_words("")
        end
        draw_subtitle_timestamp(convert_time_to_timestamp(current_playing_time))
    end
end

--- Gets the selected subtitle file path from the corresponding widget
-- @return {string} The selected subtitle path to the file
function get_selected_subtitle_file()
    local selected_subtitle_file_id = dropdown_subtitle_files:get_value()

    return subtitle_files_paths[selected_subtitle_file_id]
end

--- Gets the current playing time of the video
-- @return {number} the current playing time in seconds
function get_current_time()
    local current_time_microseconds = vlc.var.get(vlc.object.input(), "time")

    return current_time_microseconds / 1000000
end

--- Splits a subtitle in clean words
-- @param subtitle {string} The subtitle text to split
-- @return {table} The array of splitted words
function split_words(subtitle)
    -- Remove HTML tags and punctuation symbols (except apostrophe ' and hyphen -)
    local transformed_subtitle = subtitle:gsub("<.->", "")
    transformed_subtitle = transformed_subtitle:gsub("[,:;!#&/<=>@_`\"\\¡¿{}~|%%%+%$%(%)%?%^%[%]%*%.]+", "")
    transformed_subtitle = transformed_subtitle:lower()

    local words = {}
    for word in transformed_subtitle:gmatch("[^%s]+") do
        -- Remove hyphens that don't belong to the word (trailing hyphens)
        word = word:match("^%-*(.-)%-*$")
        if (word and word ~= "") then
            words[#words + 1] = word
        end
    end

    return words
end

------- Subtitle discovery -------

--- Gets the file system's paths to the found subtitles of the playing video, storing them in the corresponding global variable
function discover_subtitle_file_paths()
    subtitle_files_paths = {}

    local directory_path, filename = get_video_file_location()
    local filename_no_extension = filename:match("^(.+)%..+$")
    if (is_unix_os()) then
        directory_path = "/" .. directory_path
    end

    local filenames_in_directory = list_directory(directory_path)
    local subtitle_filenames = find_matching_filenames(filename_no_extension, filenames_in_directory, "srt")
    if (subtitle_filenames) then
        for index, subtitle_filename in ipairs(subtitle_filenames) do
            subtitle_files_paths[#subtitle_files_paths + 1] = directory_path .. subtitle_filename
        end
    else
        vlc.msg.warn("The list of filenames in the directory couldn't be retrieved: trying the default subtitle name")
        subtitle_files_paths[1] = directory_path .. filename_no_extension .. ".srt"
    end
end

--- Gets the playing video directory and filename
-- @return {string} The absolute directory path where the file is located (separated by slashes and without root slash)
-- @return {string} The name of the video file
function get_video_file_location()
    local decoded_media_uri = vlc.strings.decode_uri(vlc.input.item():uri())
    local directory_path, filename = decoded_media_uri:match("^file:///(.+/)(.+%..+)$")

    return directory_path, filename
end

--- Gets a list of filenames that have the same name as the given filename but differ in extension
-- @param target_filename {string} The filename to match (without the extension). Ex. "video"
-- @param filename_listing {table} The array of filenames to compare
-- @param extension {string} The extension to match. Ex. ".srt"
-- @return {table} The array of matching filenames. Ex. { "video.srt", "video.eng.srt", ... }
function find_matching_filenames(target_filename, filename_listing, extension)
    local matching_filenames = {}

    for index, candidate_filename in ipairs(filename_listing) do
        local has_name = candidate_filename:find(target_filename, 1, true)
        local has_extension = candidate_filename:find("%." .. extension .. "$")

        if (has_name and has_extension) then
            matching_filenames[#matching_filenames + 1] = candidate_filename
        end
    end

    return matching_filenames
end

--- Gets the list of filenames inside a given directory
-- @param path {string} The directory path separated by slashes. Ex. directory1/directory2/
-- @return {table} The array of file names inside the directory, nil if the files listing could not be retrieved
function list_directory(directory)
    local filenames = {}

    local listing_command
    if (is_unix_os()) then
        listing_command = 'ls -p "' .. directory .. '" | grep -v /'
    else
        listing_command = 'dir "' .. directory .. '" /b /a-d'
    end

    local pfile = io.popen(listing_command, "r")

    if (pfile) then
        for filename in pfile:lines() do
            filenames[#filenames + 1] = filename
        end
        pfile:close()
    else
        filenames = nil
    end

    return filenames
end

--- Detects if the current operating system is Unix like
-- @return true if the operating system is Unix like, false otherwise
function is_unix_os()
    if (vlc.config.homedir():match("^/")) then
        return true
    else
        return false
    end
end

--- Loads the complete subtitle text from a file in the corresponding global variable, returning an error message something went wrong.
-- The text is initialized to nil if there isn't a current subtitle file or something went wrong
-- @param path {string} The path to the subtitle file
-- @return {string} The error message if some I/O error occurs, nil if everything goes well
function load_subtitle_file_text(path)
    local file, error_message = io.open(path, "r")

    if (file) then
        text = file:read("*a")
        file:close()
    else
        text = nil
    end

    return error_message;
end

------- Subtitle frame extraction -------

--- Gets the subtitle entry from the subtitle file text corresponding to a specific time.
-- Fills the array containing the historic of appearance times in the process.
-- @param time {number} The time in seconds
-- @return {string} The subtitle text at the corresponding time, nil if nothing was found
function search_corresponding_subtitle_at_time(time)
    initialize_historic_appearance_times()

    local eof, exceeded, found = false, false, false
    local current_index = 1

    -- Iterates from the begining of the file's text until the subtitle is found, or there is no subtitle at that time, or the end of the file is reached
    local apperance_time_interval_limits
    while (true) do
        apperance_time_interval_limits = get_next_appearance_time_interval(current_index)
        if (apperance_time_interval_limits) then
            local appearance_time_interval = text:sub(apperance_time_interval_limits.start_index, apperance_time_interval_limits.finish_index)

            local timestamps = extract_timestamps(appearance_time_interval)
            local comparison_result = compare_time_to_interval(timestamps, time)
            if (comparison_result == 0) then
                record_appearance_time(apperance_time_interval_limits)
                found = true
                break
            elseif (comparison_result < 0) then
                -- The subtitle's appearance time has exceeded the current time
                record_appearance_time({})
                exceeded = true
                break
            else
                -- Remember the appearance time interval position
                record_appearance_time(apperance_time_interval_limits)
                current_index = apperance_time_interval_limits.finish_index
            end
        else
            record_appearance_time({})
            eof = true
            break
        end
    end

    if (found) then
        return extract_subtitle_frame_fragment_text(apperance_time_interval_limits.finish_index)
    elseif (exceeded or eof) then
        return nil
    end
end

--- Gets the next ocurrence of an appearance time interval present on the file's text starting from a given index.
-- @param from_index {number} The index in the subtitle's text to start searching from
-- @return {table} The indexes in the subtitle's text corresponding to the start and finish characters of an appearance time interval stored in a table under the keys "start_index" and "finish_index", nil if no match was found
function get_next_appearance_time_interval(from_index)
    local start_match_index, finish_match_index = string.find(text, "%s*%d+:%d+:%d+,%d+%s*-->%s*%d+:%d+:%d+,%d+%s*", from_index)

    if (start_match_index) then
        return { start_index = start_match_index, finish_index = finish_match_index }
    else
        return nil
    end
end

--- Extracts the start and finish timestamps from an appearance time interval. The appearance time interval format is: hh:mm:ss,SSS --> hh:mm:ss,SSS
-- @param apperance_time_interval {string} The line to extract the timestamps from
-- @return {table} The start and finish extracted timestamps stored in a table under the keys "start" and "finish", nil if no match was found
function extract_timestamps(apperance_time_interval)
    local start_timestamp, finish_timestamp = string.match(apperance_time_interval, "%s*(%d+:%d+:%d+,%d+)%s*-->%s*(%d+:%d+:%d+,%d+)%s*")

    if (start_timestamp) then
        return { start = start_timestamp, finish = finish_timestamp }
    else
        return nil
    end
end

--- Checks if a time in seconds is: contained, lower or greater than a given interval
-- @param interval {table} The start and finish extracted timestamps (hh:mm:ss,SSS) stored in a table under the keys "start" and "finish".
-- @param time {time} The time to compare against the interval in seconds
-- @return {number}
-- * -1 if the time is lower than the lower limit
-- *  0 if the time is between the lower and upper limits of the interval (both inclusive)
-- *  1 if the time is greater than the upper limit
function compare_time_to_interval(interval, time)
    local lower_limit, upper_limit = convert_timestamp_to_time(interval.start), convert_timestamp_to_time(interval.finish)

    if (time < lower_limit) then
        return -1
    elseif (time > upper_limit) then
        return 1
    else
        return 0
    end
end

--- Converts a timestamp in hh:mm:ss,SSS format to seconds
-- @param timestamp {string} The timestamp in hh:mm:ss,SSS format
-- @return {number} The time in seconds
function convert_timestamp_to_time(timestamp)
    local hours, minutes, seconds, millis = timestamp:match("(%d+):(%d+):(%d+),(%d+)")

    return tonumber(hours) * 3600 + tonumber(minutes) * 60 + tonumber(seconds) + tonumber(millis) / 1000
end

--- Gets the text from a given index until the end of the subtitle in which it's included
-- @param from_index {number} The index in the subtitle's text to start searching from
-- @return {string} The fragment of text corresponding to a certain subtitle frame
function extract_subtitle_frame_fragment_text(from_index)
    local current_subtitle_end, next_subtitle_start = text:find("\n%s*%d+%s*\n", from_index)

    if (current_subtitle_end) then
        return text:sub(from_index, current_subtitle_end - 1)
    else
        -- Until end of file
        return text:sub(from_index)
    end
end

------- Historic appearance times handling ------- 

--- Initializes the record of appearance times (stored as indexes in the subtitle's text corresponding to the start and finish characters of an appearance time interval)
function initialize_historic_appearance_times()
    historic_appearance_times = {}
    current_historic_apperance_time = 0
end

--- Pushes an entry containing indexes in the subtitle's text corresponding to the start and finish characters of an appearance time interval
-- in the historial of apperance times
-- @param indexes {table} The indexes in the subtitle's text corresponding to the start and finish characters of an appearance time interval stored in a table under the keys "start_index" and "finish_index"
function record_appearance_time(indexes)
    historic_appearance_times[#historic_appearance_times + 1] = indexes
    current_historic_apperance_time = current_historic_apperance_time + 1
end

--- Removes the last entry containing the indexes in the subtitle's text corresponding to the start and finish characters of an appearance time interval in the historial of apperance times
function pop_appearance_time()
    historic_appearance_times[#historic_appearance_times] = nil
    current_historic_apperance_time = current_historic_apperance_time - 1
end

--- Shows the words in the list widget corresponding to the subtitle that goes before the current one in the historic of appearance times
function navigate_backward()
    local previous_appearance_time_interval_limits, current_appearance_time_interval_limits

    if (current_historic_apperance_time > 1) then
        current_appearance_time_interval_limits = historic_appearance_times[current_historic_apperance_time]

        if (not current_appearance_time_interval_limits.start_index) then
            -- The last registered entry is empty, that means: there is no subtitle at the current time
            pop_appearance_time()
        else
            current_historic_apperance_time = current_historic_apperance_time - 1
        end
        previous_appearance_time_interval_limits = historic_appearance_times[current_historic_apperance_time]

        local subtitle = extract_subtitle_frame_fragment_text(previous_appearance_time_interval_limits.finish_index)
        show_subtitle_and_time(subtitle, previous_appearance_time_interval_limits)
    end
end

--- Shows the words in the list widget corresponding to the subtitle that goes after the current one in the historic of appearance times
function navigate_forward()
    local subtitle

    local next_apperance_time_interval_limits
    if (current_historic_apperance_time == #historic_appearance_times) then
        local current_finish_index

        local current_appearance_time_interval_limits = historic_appearance_times[current_historic_apperance_time]
        if (not current_appearance_time_interval_limits.start_index) then
            -- The last registered entry is empty, that means there is no subtitle at the current time
            pop_appearance_time()
        end

        if (current_historic_apperance_time == 0) then
            current_finish_index = 1
        else
            current_appearance_time_interval_limits = historic_appearance_times[current_historic_apperance_time]
            current_finish_index = current_appearance_time_interval_limits.finish_index
        end

        next_apperance_time_interval_limits = get_next_appearance_time_interval(current_finish_index)
        if (next_apperance_time_interval_limits) then
            record_appearance_time(next_apperance_time_interval_limits)

            subtitle = extract_subtitle_frame_fragment_text(next_apperance_time_interval_limits.finish_index)
        end
    else
        current_historic_apperance_time = current_historic_apperance_time + 1
        next_apperance_time_interval_limits = historic_appearance_times[current_historic_apperance_time]

        subtitle = extract_subtitle_frame_fragment_text(next_apperance_time_interval_limits.finish_index)
    end

    if (subtitle) then
        show_subtitle_and_time(subtitle, next_apperance_time_interval_limits)
    end
end

------- Online look up -------

--- Performs all the required tasks to look up a word in a search engine
function process_word_search()
    local selected_word = get_first_selected_word()
    local selected_search_engine_url = get_selected_search_engine().url

    if (selected_word) then
        look_up_word(selected_word, selected_search_engine_url)
    end
end

--- Looks up a word in a search engine
-- @param word {string} The word to look up
-- @param search_engine_url {string} The search engine URL to look up the word into
function look_up_word(word, search_engine_url)
    local prepared_url = build_query(word, search_engine_url)
    local hyperlink = generate_html_hyperlink(prepared_url)

    text_box_html:set_text(hyperlink .. "<p><em>Searching...</em></p>")
    dlg:update()

    local content, error_message = download_content(prepared_url)

    if (not content) then
        content = generate_html_error(error_message)
    end

    text_box_html:set_text(hyperlink .. content)
end

--- Builds the URL query to look up a word in a search engine
-- @param word {string} The word to look up
-- @param search_engine_url {string} The search engine URL to put the word into
-- @return {string} The constructed URL query
function build_query(word, search_engine_url)
    local query_place_regex = "%%s"

    return search_engine_url:gsub(query_place_regex, word)
end

--- Generates an HTML hyperlink to an URL
-- @param url {string} The URL to generate the hyperlink to
-- @return {string} The HTML hyperlink
function generate_html_hyperlink(url)
    return "<p><a href=" .. url .. "><strong>Open in browser</strong></a></p>"
end

--- Generates a red-colored HTML error message
-- @param error_message {string} The error message to represent
-- @return {string} The HTML formatted error message
function generate_html_error(error_message)
    return "<p><font color='red'>" .. error_message .. "</font></p>"
end

--- Downloads the HTML content from the given URL
-- @param url {string} The URL to download the content from
-- @return {string} The complete HTML downloaded content, nil if some problem occurred
-- @return {string} The error message if some problem occurred, nil if all was ok
function download_content(url)
    local stream, error_message = vlc.stream(url)

    if (not stream) then
        return nil, error_message
    end

    local string_buffer = {}
    repeat
        local line = stream:readline()

        if (line) then
            string_buffer[#string_buffer + 1] = line
        end
    until (not line)

    return table.concat(string_buffer)
end

--- Gets the first selected word in the list widget
-- @return {string} The first selected word, nil if nothing was selected
function get_first_selected_word()
    local selection = list_words:get_selection()

    if (selection) then
        for id, selected_word in pairs(selection) do
            return selected_word
        end
    else
        return nil
    end
end

--- Gets the selected search engine in the dropdown widget
-- @return {table} The selected search engine data ({name=..., url=...})
function get_selected_search_engine()
    local selected_search_engine_id = dropdown_search_engines:get_value()

    return search_engines[selected_search_engine_id]
end

--- Converts a number of seconds to a timestamp in hh:mm:ss format
-- @param seconds {number} The time to convert in seconds
-- @return {string} the timestamp in hh:mm:ss format
function convert_time_to_timestamp(seconds_to_convert)
    local hours = math.floor(seconds_to_convert / 3600)
    local minutes = math.floor((seconds_to_convert % 3600) / 60)
    local seconds = math.floor((seconds_to_convert % 60))

    return string.format("%02d:%02d:%02d", hours, minutes, seconds)
end

function close()
    vlc.deactivate();
end


