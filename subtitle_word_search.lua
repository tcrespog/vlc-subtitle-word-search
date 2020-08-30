--[[
Program: Subtitle Word Search
Purpose: Search words from the current subtitle file in a search engine 
Author: Tomás Crespo
License: GNU GENERAL PUBLIC LICENSE
]]

function descriptor()
    return {
        title = "Subtitle Word Search",
        version = "1.3",
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
    { name = "Urban Dictionary", url = "http://www.urbandictionary.com/define.php?term=%s" },
    { name = "Vocabulary", url = "https://www.vocabulary.com/dictionary/%s" },
    { name = "Cambridge", url = "https://dictionary.cambridge.org/dictionary/english/%s" }
}

---------- VLC entrypoints ----------

function activate()
    initialize_gui()
    initialize_subtitle_files()
    initialize_search_engines()
    load_subtitle_file()
end

function close()
    vlc.deactivate();
end

---------- Initialization functions ----------

-- gui {Gui} The Graphical User Interface.
gui = nil
-- subtitle_files {array<SubtitleFile>} Contains the candidate subtitle files.
subtitle_files = nil
-- current_subtitle_file {SubtitleFile} Contains the currently selected subtitle file.
current_subtitle_file = nil

function initialize_gui()
    gui = Gui.new()
    gui:render()
end

-- Look for the candidate subtitle files and adds them to the GUI dropdown.
function initialize_subtitle_files()
    local file_discoverer = SubtitleFileDiscoverer.new("srt")
    subtitle_files = file_discoverer:discover_files()

    for index, subtitle_file in ipairs(subtitle_files) do
        gui:inject_subtitle_file(subtitle_file:get_name(), index)
    end
end

-- Inject the search engine names in the corresponding dropdown widget.
function initialize_search_engines()
    for index, search_engine in ipairs(search_engines) do
        gui:inject_search_engine(search_engine.name, index)
    end
end

---------- GUI callback functions ----------

-- Load a subtitle file.
-- Then shows the subtitle words corresponding to the current time, or displays an error message if something went wrong.
function load_subtitle_file()
    if (current_subtitle_file) then
        current_subtitle_file:clear()
    end

    local subtitle_file_index = gui:get_selected_subtitle_file_index()
    current_subtitle_file = subtitle_files[subtitle_file_index]

    if (current_subtitle_file) then
        local subtitle_delay = vlc.var.get(vlc.object.input(), "spu-delay")
        local video_length = vlc.var.get(vlc.object.input(), "length")
        local srt_reader = SrtReader.new(current_subtitle_file:get_path(), subtitle_delay, video_length)
        local subtitle_lines, error_message = srt_reader:read()

        if (error_message) then
            gui:print_error_message(error_message)
        else
            current_subtitle_file:set_subtitle_lines(subtitle_lines)
            capture_words_at_now()
        end
    else
        local video_directory, video_filename = get_video_file_location()
        gui:print_error_message("No subtitle files found at '" .. video_directory .. "' for the file '" .. video_filename .. "'")
    end
end

-- Show the words of the subtitle appearing at the current timestamp in the corresponding list widget.
-- Displays an error message if something goes wrong.
function capture_words_at_now()
    if (not current_subtitle_file) then
        return
    end

    local current_playing_timestamp = Timestamp.now()
    local subtitle_line = current_subtitle_file:search_line_at(current_playing_timestamp)

    show_subtitle_and_timestamp(subtitle_line, current_playing_timestamp)
end

-- Show the words in the list widget corresponding to the current subtitle.
function navigate_still()
    navigate(0)
end

-- Show the words in the list widget corresponding to the subtitle that goes before the current one.
function navigate_backward()
    navigate(-1)
end

-- Show the words in the list widget corresponding to the subtitle that goes after the current one.
function navigate_forward()
    navigate(1)
end

-- Show the words in the list widget corresponding to the subtitle shifted `n` lines.
-- @param n {number} The number of lines to shift.
function navigate(n)
    if (not current_subtitle_file) then
        return
    end

    local subtitle_line = current_subtitle_file:shift_lines(n)
    if (subtitle_line) then
        show_subtitle_and_timestamp(subtitle_line, subtitle_line:get_start())
    end
end

-- Show the words of a subtitle along with the associated timestamp in the corresponding list widget.
-- @param subtitle_line {SubtitleLine} The subtitle line to show split.
-- @param timestamp {Timestamp} The associated appearance timestamp.
function show_subtitle_and_timestamp(subtitle_line, timestamp)
    if (subtitle_line) then
        gui:inject_subtitle_words(subtitle_line:get_content())
    else
        gui:inject_subtitle_words("")
    end
    gui:print_timestamp(timestamp)
end

-- Read the timestamp corresponding to the current subtitle line and visits that time in the video.
function go_to_subtitle_timestamp()
    if (not current_subtitle_file) then
        return
    end

    local current_subtitle_line = current_subtitle_file:shift_lines(0)

    vlc.var.set(vlc.object.input(), "time", current_subtitle_line:get_start():to_microseconds())
end

-- Look up a word in a search engine.
function search_word()
    local selected_word = gui:get_first_selected_word()

    local selected_search_engine_index = gui:get_selected_search_engine_index()
    local selected_search_engine_url = search_engines[selected_search_engine_index].url

    if (not selected_word) then
        return
    end

    local is_remove_head = gui:get_remove_head_flag()
    local online_search = OnlineSearch.new(selected_search_engine_url, selected_word, is_remove_head)
    local hyperlink = online_search:generate_html_hyperlink()

    gui:print_html(hyperlink .. "<p><em>Searching...</em></p>")
    gui:update()

    local content, error_message = online_search:request()
    if (content) then
        gui:print_html(hyperlink .. content)
    else
        gui:print_error_message(hyperlink .. error_message)
    end
end

---------- Classes ----------

-- Class: Gui.
-- Renders the GUI (Graphical User Interface).
Gui = {}
Gui.__index = Gui

-- Constructor method. Create the GUI instance.
function Gui.new()
    local self = setmetatable({}, Gui)
    -- dialog {vlc.dialog} The VLC dialog.
    self.dialog = nil
    -- files_dropdown {vlc.dropdown} The subtitle files dropdown.
    self.files_dropdown = nil
    -- lower_checkbox {vlc.checkbox} The text to lower case checkbox flag.
    self.lower_checkbox = nil
    -- symbol_checkbox {vlc.checkbox} The text to punctuation strip checkbox flag.
    self.symbol_checkbox = nil
    -- timestamp_label {vlc.label} The current timestamp label.
    self.timestamp_label = nil
    -- words_list {vlc.list} The words list widget.
    self.words_list = nil
    -- search_engines_dropdown {vlc.dropdown} The search engines dropdown.
    self.search_engines_dropdown = nil
    -- remove_head_checkbox {vlc.checkbox} The HTML remove head checkbox flag.
    self.remove_head_checkbox = nil
    -- html_text_box {vlc.html} The text box to render the web HTML.
    self.html_text_box = nil
    -- last_row {number} The last row in the grid being constructed.
    self.last_row = 1
    return self
end

-- Render the VLC extension grid dialog.
function Gui:render()
    self.dialog = vlc.dialog("Subtitle Word Search")

    self:draw_file_section()
    self:draw_subtitle_section()
    self:draw_online_search_section()

    self.dialog:show()
end

-- Increment the index of the last row in the GUI and returns the value previous to the increment.
-- Equivalent to the typical construct `n++` of other programming languages.
-- @return {number} The last row number value previous to the increment.
function Gui:increment_row()
    local previous_last_row = self.last_row
    self.last_row = self.last_row + 1
    return previous_last_row
end

-- Draw the subtitle files selector section.
function Gui:draw_file_section()
    self.dialog:add_label("<h2>Subtitles file</h2>", 1, self:increment_row(), 5, 1)
    self.files_dropdown = self.dialog:add_dropdown(1, self.last_row, 1)
    self.dialog:add_button("Load", load_subtitle_file, 2, self:increment_row())
end

-- Draw the subtitle navigation and word selection section.
function Gui:draw_subtitle_section()
    self.dialog:add_label("<h2>Subtitle words</h2>", 1, self:increment_row())

    self.dialog:add_button("Transform", navigate_still, 1, self.last_row)
    self.lower_checkbox = self.dialog:add_check_box("Lower", true, 2, self.last_row)
    self.symbol_checkbox = self.dialog:add_check_box("Symbols", false, 3, self:increment_row())

    self.dialog:add_button("Refresh", capture_words_at_now, 1, self.last_row)
    self.dialog:add_button("<<", navigate_backward, 2, self.last_row)
    self.timestamp_label = self.dialog:add_label("00:00:00", 3, self.last_row)
    self.dialog:add_button(">>", navigate_forward, 4, self.last_row)
    self.dialog:add_button("Go", go_to_subtitle_timestamp, 5, self:increment_row())

    self.words_list = self.dialog:add_list(1, self:increment_row(), 5, 1)
end

-- Draw the search section.
function Gui:draw_online_search_section()
    self.dialog:add_label("<h2>Word Search</h2>", 1, self:increment_row())
    self.remove_head_checkbox = self.dialog:add_check_box("Remove <head> tag", false, 1, self:increment_row())
    self.search_engines_dropdown = self.dialog:add_dropdown(1, self.last_row)
    self.dialog:add_button("Search", search_word, 2, self:increment_row())
    self.html_text_box = self.dialog:add_html("", 1, self.last_row, 5, 10)
end

-- Add a file name to the corresponding dropdown widget.
-- @param name {string} The subtitle file name.
-- @param index {number} The search engine index in the global array of subtitle files.
function Gui:inject_subtitle_file(name, index)
    self.files_dropdown:add_value(name, index)
end

-- Add a search engine to the corresponding dropdown widget.
-- @param name {string} The search engine name.
-- @param index {number} The search engine index in the global array of engines.
function Gui:inject_search_engine(name, index)
    self.search_engines_dropdown:add_value(name, index)
end

-- Show the split words from a subtitle in the list widget.
-- @param subtitle {string} the subtitle to show.
function Gui:inject_subtitle_words(text)
    self.words_list:clear()

    local to_lower = self.lower_checkbox:get_checked()
    local strip_punctuation = not self.symbol_checkbox:get_checked()

    local words = split_words(text, to_lower, strip_punctuation)
    for index, word in ipairs(words) do
        self.words_list:add_value(word, index)
    end
end

-- Get the index of the selected subtitle file in the corresponding dropdown widget.
-- @return {number} The index of the selected file.
function Gui:get_selected_subtitle_file_index()
    return self.files_dropdown:get_value()
end

-- Get the selected search engine index in the corresponding dropdown widget.
-- @return {number} The selected search engine index.
function Gui:get_selected_search_engine_index()
    return self.search_engines_dropdown:get_value()
end

-- Get the first selected word in the corresponding list widget.
-- @return {string} The first selected word, `nil` if nothing was selected
function Gui:get_first_selected_word()
    local selection = self.words_list:get_selection()

    if (selection) then
        for index, selected_word in pairs(selection) do
            return selected_word
        end
    else
        return nil
    end
end

-- Gets the value of the remove HTML head checkbox flag.
-- @return {boolean} `true` if the checkbox is checked, `false` otherwise.
function Gui:get_remove_head_flag()
    return self.remove_head_checkbox:get_checked()
end

-- Print a timestamp in the specific label.
-- @param timestamp {Timestamp} The timestamp to print.
function Gui:print_timestamp(timestamp)
    self.timestamp_label:set_text(timestamp:to_string())
end

-- Print a HTML text in the corresponding widget.
-- @param html {string} The HTML text content.
function Gui:print_html(html)
    self.html_text_box:set_text(html)
end

-- Print a red-colored HTML error message.
-- @param error_message {string} The error message to print.
function Gui:print_error_message(error_message)
    local html_error_message = "<p><font color='red'>" .. error_message .. "</font></p>"
    self:print_html(html_error_message)
end

-- Update the GUI. Useful to render partial updates before a method returns.
function Gui:update()
    self.dialog:update()
end


-- Class: OnlineSearch.
-- Represents a search in a search engine.
OnlineSearch = {}
OnlineSearch.__index = OnlineSearch

-- Constructor method. Create an online search.
-- @param search_engine_url {string} The search engine URL.
-- @return {OnlineSearch} The search engine instance.
function OnlineSearch.new(search_engine_url, word, is_remove_head)
    local self = setmetatable({}, OnlineSearch)
    -- search_engine_url {string} The search engine URL with a placeholder.
    self.search_engine_url = search_engine_url
    -- is_remove_head {boolean} If `true`, removes the HTML <head> tag from the downloaded content.
    self.is_remove_head = is_remove_head
    -- query_url {string} The constructed URL composed of engine URL and word.
    self.prepared_url = nil
    self:prepare_url(word)
    return self
end

-- Request the query result.
-- @return {string} The query result content, `nil` if some error occurs.
-- @return {string} An error message, `nil` if everything was good.
function OnlineSearch:request()
    local downloaded_content = download_content(self.prepared_url)
    if (self.is_remove_head) then
        return remove_html_head(downloaded_content)
    else
        return downloaded_content
    end
end

-- Build the URL query to look up a word in a search engine.
-- @param word {string} The word to look up.
function OnlineSearch:prepare_url(word)
    local query_place_regex = "%%s"
    self.prepared_url = self.search_engine_url:gsub(query_place_regex, word)
end

-- Generates an HTML hyperlink to the query URL.
-- @return {string} The HTML hyperlink.
function OnlineSearch:generate_html_hyperlink()
    return "<p><a href=" .. self.prepared_url .. "><strong>Open in browser</strong></a></p>"
end


-- Class: SubtitleFileDiscoverer.
-- Discovers the candidate subtitle files in the filesystem.
SubtitleFileDiscoverer = {}
SubtitleFileDiscoverer.__index = SubtitleFileDiscoverer

-- Constructor method. Create a subtitle file discoverer.
-- @param extension {string} The extension of the file to discover. Ex. "srt".
-- @return {SubtitleFileDiscoverer} The subtitle discoverer instance.
function SubtitleFileDiscoverer.new(extension)
    local self = setmetatable({}, SubtitleFileDiscoverer)
    -- extension {string} The file extension to discover
    self.extension = extension
    return self
end

-- Get the file system's paths to the found subtitles of the playing video
-- @return {array<SubtitleFile>} The array of discovered files.
function SubtitleFileDiscoverer:discover_files()
    local subtitle_files = {}

    local video_dir_path, video_filename = get_video_file_location()
    local video_filename_no_ext = video_filename:match("^(.+)%..+$")
    if (is_unix_os()) then
        video_dir_path = "/" .. video_dir_path
    end

    local filenames_in_directory = list_directory(video_dir_path)
    local subtitle_filenames = self:find_matching_filenames(video_filename_no_ext, filenames_in_directory)
    if (subtitle_filenames) then
        for index, subtitle_filename in ipairs(subtitle_filenames) do
            local absolute_path = video_dir_path .. subtitle_filename
            subtitle_files[#subtitle_files + 1] = SubtitleFile.new(absolute_path, subtitle_filename)
        end
    else
        vlc.msg.warn("The list of filenames in the directory couldn't be retrieved: trying the default subtitle name")
        local filename = video_filename_no_ext .. "." .. self.extension
        local absolute_path = video_dir_path .. filename
        subtitle_files[1] = SubtitleFile.new(absolute_path, filename)
    end

    return subtitle_files
end

-- Get an array of filenames that have the same name as the given filename but differ in extension.
-- @param target_filename {string} The filename to match (without the extension). Ex. "video".
-- @param filename_listing {array<string>} The array of filenames to compare.
-- @param extension {string} The extension to match. Ex. ".srt".
-- @return {array<string>} The array of matching filenames. Ex. { "video.srt", "video.eng.srt", ... }.
function SubtitleFileDiscoverer:find_matching_filenames(target_filename, filename_listing)
    local matching_filenames = {}

    for index, candidate_filename in ipairs(filename_listing) do
        local has_name = candidate_filename:find(target_filename, 1, true)
        local has_extension = candidate_filename:find("%." .. self.extension .. "$")

        if (has_name and has_extension) then
            matching_filenames[#matching_filenames + 1] = candidate_filename
        end
    end

    return matching_filenames
end


-- Class: SubtitleFile.
-- Represents a subtitle file.
SubtitleFile = {}
SubtitleFile.__index = SubtitleFile

-- Constructor method. Create a subtitle file.
-- @param path {string} The absolute path of the file.
-- @param name {string} The name of the file.
-- @return {SubtitleFile} The subtitle file instance.
function SubtitleFile.new(path, name)
    local self = setmetatable({}, SubtitleFile)
    -- path {string} The path of the subtitle file.
    self.path = path
    -- name {string} The name of the subtitle file.
    self.name = name
    -- subtitle_lines {array<SubtitleLine>} The subtitle lines in the file.
    self.subtitle_lines = nil
    -- current_line_index {number} The index of the current subtitle.
    self.current_line_index = nil
    return self
end

-- Set the subtitle lines read from the file.
-- @param {array<SubtitleLine>} The array of subtitle lines in order of appearance.
function SubtitleFile:set_subtitle_lines(subtitle_lines)
    self.subtitle_lines = subtitle_lines
end

-- Get the name of the subtitle file.
-- @return {string} The name of the subtitle file.
function SubtitleFile:get_name()
    return self.name
end

-- Get the path of the subtitle file.
-- @return {string} The path of the subtitle file.
function SubtitleFile:get_path()
    return self.path
end

-- Search the subtitle line at the give timestamp.
-- Performs a binary search over the ordered subtitle lines.
-- Updates the value of the current line index, which would point to an index with fractional part if nothing was found.
-- @param {Timestamp} The timestamp to search the subtitle at.
-- @return {SubtitleLine} The found line, `nil` if no line was found for the timestamp.
function SubtitleFile:search_line_at(timestamp)
    local lower_bound, upper_bound = 1, #self.subtitle_lines

    local found_line, middle_index
    repeat
        local half_distance = math.floor((upper_bound - lower_bound) / 2)
        middle_index = lower_bound + half_distance

        local current_line = self.subtitle_lines[middle_index]
        local is_in_interval = current_line:is_in_interval(timestamp)
        if (is_in_interval) then
            found_line = current_line
            self.current_line_index = middle_index
            break
        else
            local comparison = timestamp:compare_to(current_line:get_start())
            if (comparison > 0) then
                lower_bound = middle_index
            else
                upper_bound = middle_index
            end
        end
    until (half_distance == 0)

    if (not found_line) then
        self:set_invalid_line_index(lower_bound, upper_bound, timestamp)
    end

    return found_line
end

-- Set an index with fractional part, indicating the place near two consecutive indices where a value not found should be.
-- @param lower_bound {number} The lower bound index of the value proximity.
-- @param upper_bound {number} The upper bound index of the value proximity.
-- @param timestamp {Timestamp} The not found value timestamp.
function SubtitleFile:set_invalid_line_index(lower_bound, upper_bound, timestamp)
    local lower_line_timestamp = self.subtitle_lines[lower_bound]:get_start()
    local upper_line_timestamp = self.subtitle_lines[upper_bound]:get_start()

    if (timestamp:compare_to(lower_line_timestamp) < 0) then
        self.current_line_index = lower_bound - 0.5
    elseif (timestamp:compare_to(upper_line_timestamp) > 0) then
        self.current_line_index = upper_bound + 0.5
    else
        self.current_line_index = lower_bound + 0.5
    end
end

-- Check if the current index is pointing to an actual subtitle, or rather to a middle ground.
-- @return {boolean} `true` if the current line index points to a valid line, `false` otherwise.
function SubtitleFile:is_valid_line_index()
    return (self.current_line_index == math.floor(self.current_line_index))
end

-- Get the subtitle line shifting `n` lines from the current line.
-- The lines to shift must be between -1, 0 and +1. A value of 0 returns the current line, or `nil` if not pointing to a valid line.
-- @param n {number} The number of lines to shift.
-- @return The shifted line, `nil` if the shift exceeds the array bounds or doesn't point to anything.
function SubtitleFile:shift_lines(n)
    local is_valid_line_index = self:is_valid_line_index()
    if (not is_valid_line_index and (n == 0)) then
        return nil
    end

    local new_line_index
    if (is_valid_line_index) then
        new_line_index = self.current_line_index + n
    else
        new_line_index = self.current_line_index + 0.5 * n
    end

    if ((new_line_index < 1) or (new_line_index > #self.subtitle_lines)) then
        return nil
    end

    self.current_line_index = new_line_index
    return self.subtitle_lines[new_line_index]
end

-- Clear the subtitle lines of the file.
-- Note the current line index is not cleared.
function SubtitleFile:clear()
    self.subtitle_lines = nil
end


-- Class: SrtReader.
-- Reads an SRT file.
SrtReader = {}
SrtReader.__index = SrtReader

-- Reader state machine values
SrtReader.READING_NUMBER = 0
SrtReader.READING_INTERVAL = 1
SrtReader.READING_CONTENT = 2

-- Constructor method. Creates a reader.
-- @param filepath {string} The path of the file to read.
-- @param subtitle_delay_microseconds {number} The subtitle delay in microseconds. Can be negative.
-- @return {SrtReader} The SRT reader instance.
function SrtReader.new(filepath, subtitle_delay_microseconds, video_length_microseconds)
    local self = setmetatable({}, SrtReader)
    -- filepath {string} The path of the file to read.
    self.filepath = filepath
    -- subtitle_delay_microseconds {number} The subtitle delay in microseconds.
    self.subtitle_delay_microseconds = subtitle_delay_microseconds
    -- video_length_microseconds {number} The length of the video in microseconds.
    self.video_length_microseconds = video_length_microseconds
    -- current_line_number {number} The line number of the text file being read.
    self.current_line_number = 1
    -- subtitle_lines {array<SubtitleLine>} The subtitle lines in the file.
    self.subtitle_lines = {}
    -- current_index {number} The index corresponding to the current subtitle line being read.
    self.current_index = 1
    -- current_number {number} The number of the subtitle line being read.
    self.current_number = 1
    -- current_subtitle_line {SubtitleLine} The subtitle line being constructed.
    self.current_subtitle_line = nil
    -- state {number} The current state in the reader's state machine
    self.current_state = SrtReader.READING_NUMBER
    return self
end

-- Read the file extracting all subtitle lines.
-- @return {array<SubtitleLine>} The resulting subtitle lines.
-- @return {string} An error message if some I/O error or processing occurs, nil if everything goes well
function SrtReader:read()
    local file, error_message = io.open(self.filepath, "r")
    if (not file) then
        return nil, error_message
    end

    self.current_subtitle_line = SubtitleLine.new()
    for line in file:lines() do
        error_message = self:process_line(line)
        if (error_message) then
            file:close()
            return nil, error_message
        end
    end

    file:close()
    return self.subtitle_lines
end

-- Process a file line depending on the state machine status.
-- @param line {string} The file line to read.
-- @return {string} An error message if something goes wrong, `nil` if everything goes well
function SrtReader:process_line(line)
    local error_message
    if (self.current_state == SrtReader.READING_NUMBER) then
        error_message = self:process_number(line)
    elseif (self.current_state == SrtReader.READING_INTERVAL) then
        error_message = self:process_interval(line)
    elseif (self.current_state == SrtReader.READING_CONTENT) then
        self:process_content(line)
    end

    self.current_line_number = self.current_line_number + 1
    return error_message
end

-- Process a file line looking for a subtitle number.
-- @param line {string} The file line to read.
-- @return {string} An error message if something goes wrong, `nil` if everything goes well.
function SrtReader:process_number(line)
    if (is_blank(line)) then return end

    local error_message = self:read_number(line)
    self.current_state = SrtReader.READING_INTERVAL

    return error_message
end

-- Process a file line looking for a subtitle appearance interval.
-- @param line {string} The file line to read.
-- @return {string} An error message if something goes wrong, `nil` if everything goes well.
function SrtReader:process_interval(line)
    if (is_blank(line)) then return end

    local error_message = self:read_interval(line)
    self.current_state = SrtReader.READING_CONTENT

    return error_message
end

-- Process a file line looking for subtitle content.
-- @param line {string} The file line to read.
function SrtReader:process_content(line)
    if (is_blank(line)) then
        if (self.current_subtitle_line.start:is_in_video_bounds(self.video_length_microseconds)) then
            -- Save the subtitle line only if the start timestamp is within the video bounds
            self.subtitle_lines[self.current_index] = self.current_subtitle_line
            self.current_index = self.current_index + 1
        end

        self.current_state = SrtReader.READING_NUMBER
        self.current_subtitle_line = SubtitleLine.new()
        return
    end

    self:read_content(line)
end

-- Read the line containing the number of the current subtitle.
-- Checks if the number is expected.
-- @param line {string} The file line to read.
-- @return {string} The error message if something goes wrong, `nil` if everything goes well
function SrtReader:read_number(line)
    local number = line:match("^%s*(%d+)%s*$")
    if (not number) then
        return "Malformed subtitle number on line " .. self.current_line_number .. "."
    end

    local number_as_number = tonumber(number)
    if (number_as_number ~= self.current_number) then
        return "Out of place subtitle found on line " .. self.current_line_number .. "."
    end

    self.current_number = self.current_number + 1
end

-- Read the line containing the interval appearance time of the current subtitle.
-- Set the state in the current subtitle line under construction.
-- @param line {string} The file line to read.
-- @return {string} The error message if something goes wrong, `nil` if everything goes well
function SrtReader:read_interval(line)
    local start_text, finish_text = line:match("^%s*(%d+:%d+:%d+,%d+)%s*-->%s*(%d+:%d+:%d+,%d+)%s*$")
    if (not start_text or not finish_text) then
        return "Malformed subtitle interval on line " .. self.current_line_number .. "."
    end

    local start = Timestamp.of_text(start_text):add_microseconds(self.subtitle_delay_microseconds)
    local finish = Timestamp.of_text(finish_text):add_microseconds(self.subtitle_delay_microseconds)
    self.current_subtitle_line:set_start(start)
    self.current_subtitle_line:set_finish(finish)
end

-- Read the line containing the current subtitle text content.
-- Appends the content to the overall subtitle under construction.
-- @param line {string} The file line to read.
function SrtReader:read_content(line)
    self.current_subtitle_line:append_content(line)
end


-- Class: SubtitleLine.
-- Class representing a subtitle line with its content and appearance timestamp interval.
SubtitleLine = {}
SubtitleLine.__index = SubtitleLine

-- Constructor method. Create an empty subtitle line to be filled.
-- @return {SubtitleLine} The subtitle line instance.
function SubtitleLine.new()
    local self = setmetatable({}, SubtitleLine)
    -- start {Timestamp} The start timestamp of the appearance interval.
    self.start = nil
    -- finish {Timestamp} The finish timestamp of the appearance interval.
    self.finish = nil
    -- content {string} The text content of the subtitle.
    self.content = ""
    return self
end

-- Set the start timestamp of the appearance interval.
-- @param start {Timestamp} The start timestamp of the appearance interval.
function SubtitleLine:set_start(start)
    self.start = start
end

-- Set the finish timestamp of the appearance interval.
-- @param finish {Timestamp} The finish timestamp of the appearance interval.
function SubtitleLine:set_finish(finish)
    self.finish = finish
end

-- Append content to the subtitle line.
-- @param content {string} The text content to append.
function SubtitleLine:append_content(content)
    self.content = self.content .. " " .. content
end

-- Get the start timestamp of the appearance interval.
-- @return {Timestamp} The start timestamp of the appearance interval.
function SubtitleLine:get_start()
    return self.start
end

-- Get the content of the subtitle line.
-- @return {string} The content of the subtitle.
function SubtitleLine:get_content()
    return self.content
end

-- Check whether a timestamp is contained in the subtitle appearance interval (both inclusive).
-- @param timestamp {Timestamp} The timestamp to check.
-- @return {boolean} True if the timestamp is in the interval, false otherwise.
function SubtitleLine:is_in_interval(timestamp)
    return (timestamp:compare_to(self.start) >= 0) and (timestamp:compare_to(self.finish) <= 0)
end


-- Class: Timestamp.
-- Class representing a player timestamp.
Timestamp = {}
Timestamp.__index = Timestamp

-- Constructor method. Creates an empty timestamp instance.
-- @return {Timestamp} The timestamp instance.
function Timestamp.new()
    local self = setmetatable({}, Timestamp)
    -- text {string} The timestamp in <hh:mm:ss,fff> format.
    self.text = nil
    -- microseconds {number} The timestamp in microseconds.
    self.microseconds = nil
    return self
end

-- Factory method. Create a new timestamp from text in <hh:mm:ss,fff format>.
-- Computes the equivalent microseconds.
-- @param text {string} The timestamp in <hh:mm:ss,fff> format.
-- @return {Timestamp} The timestamp instance.
function Timestamp.of_text(text)
    local instance = Timestamp.new()
    instance.text = text

    local hours, minutes, seconds, millis = text:match("(%d+):(%d+):(%d+),(%d+)")
    instance.microseconds = (tonumber(hours) * 3600 + tonumber(minutes) * 60 + tonumber(seconds) + tonumber(millis) / 1000) * 1000000

    return instance
end

-- Factory method. Create a new timestamp from microseconds.
-- Computes the text representation in <hh:mm:ss,fff> format.
-- @param total_microseconds {number} The number of microseconds.
-- @return {Timestamp} The timestamp instance.
function Timestamp.of_microseconds(total_microseconds)
    local instance = Timestamp.new()
    instance.microseconds = total_microseconds

    local milliseconds = math.floor((total_microseconds % 1000000) / 1000)
    local hours = math.floor(total_microseconds / 3600000000)
    local minutes = math.floor((total_microseconds % 3600000000) / 60000000)
    local seconds = math.floor((total_microseconds % 60000000) / 1000000)

    instance.text = string.format("%02d:%02d:%02d,%03d", hours, minutes, seconds, milliseconds)

    return instance
end

-- Factory method. Create a new timestamp from the playing time of the video.
-- @return {Timestamp} The timestamp instance.
function Timestamp.now()
    local playing_time_microseconds = vlc.var.get(vlc.object.input(), "time")
    return Timestamp.of_microseconds(playing_time_microseconds)
end

-- Get a representation of the timestamp in <hh:mm:ss> format.
-- @return {string} The timestamp in <hh:mm:ss> format.
function Timestamp:to_string()
    return self.text:sub(1, -5)
end

-- Get a representation of the timestamp in microseconds.
-- @return {number} The timestamp in microseconds.
function Timestamp:to_microseconds()
    return self.microseconds
end

-- Add a number of microseconds to a timestamp. Returns a new instance.
-- @param microseconds {number} The number of microseconds to add; can be negative.
-- @return {Timestamp} The resulting new timestamp instance.
function Timestamp:add_microseconds(microseconds)
    local result_microseconds = self.microseconds + microseconds
    return Timestamp.of_microseconds(result_microseconds)
end


-- Compares this timestamp to the given timestamp.
-- @param t {Timestamp} The timestamp to compare to.
-- @return {number} A negative number if this is lower than `t`, a positive number if this is greater than `t`, zero if both are equal.
function Timestamp:compare_to(t)
    if (self.microseconds < t.microseconds) then
        return -1
    elseif (self.microseconds > t.microseconds) then
        return 1
    else
        return 0
    end
end

-- Checks whether a timestamp is within the bounds of the video length or not.
-- @return {boolean} `true` if is greater than 0 and lower than the video length, `false` otherwise.
function Timestamp:is_in_video_bounds(video_length_microseconds)
    return ((self.microseconds >= 0) and (self.microseconds <= video_length_microseconds))
end

---------- Utility functions ----------

-- Check if a string is a blank string (empty or only blanks).
-- @param s {string} The string to check.
-- @return {boolean} `true` if the string is a blank string, `false` otherwise.
function is_blank(s)
    if (s:find("^%s*$")) then
        return true
    end

    return false
end

-- Check if the current operating system is Unix-like.
-- @return {boolean} `true` if the operating system is Unix-like, `false` otherwise.
function is_unix_os()
    if (vlc.config.homedir():find("^/")) then
        return true
    end

    return false
end

-- Get the list of filenames inside a given directory.
-- @param path {string} The directory path separated by slashes. Ex. "directory1/directory2/".
-- @return {array} The array of file names inside the directory, `nil` if the files listing could not be retrieved.
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

-- Get the playing video directory and filename.
-- @return {string} The absolute directory path where the file is located (separated by slashes and without root slash).
-- @return {string} The name of the video file.
function get_video_file_location()
    local decoded_media_uri = vlc.strings.decode_uri(vlc.input.item():uri())
    local directory_path, filename = decoded_media_uri:match("^file:///(.+/)(.+%..+)$")

    return directory_path, filename
end

-- Split an HTML text in clean and separated words.
-- @param html_text {string} The HTML text to split.
-- @param to_lower {boolean} If true, transform to lower case, otherwise keep as it is.
-- @param strip_punctuation {boolean} If true, remove punctuation symbols, otherwise keep as it is.
-- @return {array<string>} The array of split words
function split_words(html_text, to_lower, strip_punctuation)
    -- Remove HTML tags.
    local transformed_text = html_text:gsub("<.->", "")
    if (to_lower) then
        -- To lower case
        transformed_text = transformed_text:lower()
    end
    if (strip_punctuation) then
        -- Remove punctuation symbols (except apostrophe ' and hyphen -)
        transformed_text = transformed_text:gsub("[,:;!#&/<=>@_`\"\\¡¿{}~|%%%+%$%(%)%?%^%[%]%*%.]+", "")
    end

    local words = {}
    for word in transformed_text:gmatch("[^%s]+") do
        -- Remove hyphens that don't belong to the word (trailing hyphens)
        word = word:match("^%-*(.-)%-*$")
        if (word and word ~= "") then
            words[#words + 1] = word
        end
    end

    return words
end

-- Removes the HTML "<head>" element from an HTML text.
-- @param html_text {string} The HTML text to strip the head element from.
-- @return {string} The resulting HTML text
function remove_html_head(html_text)
    return html_text:gsub("<head>.-</head>", "")
end

-- Download the content (usually HTML) from the given URL.
-- @param url {string} The URL to download the content from.
-- @return {string} The complete HTML downloaded content, `nil` if some problem occurred.
-- @return {string} The error message if some problem occurred, `nil` if all was ok.
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