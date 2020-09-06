# vlc-subtitle-word-search

Search for words in the SRT subtitle files of your videos playing in VLC.

# Synopsis

With this VLC extension you can search on web search engines the words displayed in the SRT subtitles of a video.
This way you can look up online dictionaries to get translations, meanings, and others.

The extension is published at [addons.videolan.org](http://addons.videolan.org/content/show.php/Subtitle+Word+Search?content=175924).

## Versions
To download the specific versions check [releases](https://github.com/tcrespog/vlc-subtitle-word-search/releases):

### v1.3
Tested with:
* Windows 10: VLC 3.0.8
* Ubuntu 20.04: VLC 3.0.8
### v1.2
Tested with:
* Windows 10: VLC 3.0.7.1
### v1.1
Tested with:
* Windows 10: VLC 2.2.2
* Linux Mint 17.3: VLC 2.1.6

# Installation

Copy the `subtitle_word_search.lua` file in one of the following directories depending upon your operating system, and the availability you want for other users:

* Windows
	* All users: `Program Files\VideoLAN\VLC\lua\extensions\`
	* Current user: `%APPDATA%\vlc\lua\extensions\`
* Mac OS X
	* All users: `/Applications/VLC.app/Contents/MacOS/share/lua/extensions/`
	* Current user: `/Users/%your_name%/Library/ApplicationSupport/org.videolan.vlc/lua/extensions/`
* Linux
	* All users: `/usr/lib/vlc/lua/playlist/ or /usr/share/vlc/lua/extensions/`
	* Current user: `~/.local/share/vlc/lua/extensions/`

# Help

## Usage

* Open the extension clicking the *View > Subtitle Word Search* menu.
* The extension looks for all the external .srt subtitle files located in the same directory of the movie file with the same name as the video file, the same subtitles that VLC detects automatically.
	* Select a subtitle file from the dropdown widget and load it clicking the **Load** button (when the extension is open, one subtitle file will be loaded by default).
	* The subtitle track synchronization **delay** is taken into account. Once you change it, click the **Load** button to apply it.
* The split words corresponding to the current playing time of the movie are displayed in a list.
* Transform the text checking the **Lower** (transform to lower case) or **Symbol** (keep punctuation symbols) boxes and clicking the **Transform** button. The transformations will be performed anyway for the next subtitles.
* Navigate through the subtitles behind/ahead of the current time clicking the **<<** and **>>** buttons.
* Jump to the location in the video of the subtitle you are viewing with the **Go** button.
* Forward the playing time, click the **Refresh** button and see the updated subtitles.
* Select a word, select a search engine, and click the **Search** button.
	* The web content will be displayed in the box at the bottom. You can also open the query link in your browser clicking the generated **Open in browser** link.
	* Sometimes, the style of some web pages is not rendered properly, you can try getting rid of the styles by removing the HTML `<head>` tag. Just check the **Remove &lt;head&gt; tag** box before making a search. 

## Tips

### Encode subtitle files as UTF-8
VLC extensions work better with UTF-8 encoded text. To make sure most of the special symbols of the file are displayed correctly make sure the subtitle file you load is encoded as UTF-8.

### Add your custom search engines
Open the `subtitle_word_search.lua` with a text editor and modify the variable `search_engines` adding new entries as in the example below.
```lua
search_engines = {
	{name = "Wikitionary", url = "http://en.wiktionary.org/wiki/%s"},
	{name = "Wikipedia", url = "https://en.wikipedia.org/wiki/%s"},
	{name = "My search engine", url = "http://www.mysearchengine.url/%s"} --New search engine!
}
```
Make sure the search engine URL has the `%s` text in place of the query text.

### Keep the extension opened
While watching a movie, open the extension and keep it open. Whenever you want to look up a word: pause the video, check the extension, click the refresh button and make your search.

### Use it to hide subtitles
You may not be interested in seeing the subtitles to help you practice your listening skills. You can disable the subtitles and use the extension to check just those sentences that you didn't get right.

## Demonstration GIFs

The following images were taken for v1.1, but the current interface is similar.

### Load another subtitle file

![alt text](https://raw.githubusercontent.com/tcrespog/vlc-subtitle-word-search/static/demonstrations/load.gif "Load a subtitle demonstration")

### Navigate through the subtitles

![alt text](https://raw.githubusercontent.com/tcrespog/vlc-subtitle-word-search/static/demonstrations/navigation.gif "Navigate subtitles demonstration")

### Search for a word

![alt text](https://raw.githubusercontent.com/tcrespog/vlc-subtitle-word-search/static/demonstrations/search.gif "Search for a word demonstration")

### Refresh the current time's subtitle

![alt text](https://raw.githubusercontent.com/tcrespog/vlc-subtitle-word-search/static/demonstrations/refresh.gif "Refresh the subtitle demonstration")

# Contribution

* The extension was created using the VLC Lua guide in this specific version:
    * [README.txt](https://github.com/videolan/vlc/blob/062edb354454161e431cb50e87e79e439968a2c4/share/lua/README.txt)
    * You can check the [history](https://github.com/videolan/vlc/commits/master/share/lua/README.txt) of the file to track changes in the API.
* The VLC [forum](https://forum.videolan.org/viewforum.php?f=29) is useful to solve doubts about plugin development.