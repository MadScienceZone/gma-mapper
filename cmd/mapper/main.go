/*
########################################################################################
#  _______  _______  _______                ___       ______       __     __           #
# (  ____ \(       )(  ___  )              /   )     / ___  \     /  \   /  \          #
# | (    \/| () () || (   ) |             / /) |     \/   \  \    \/) )  \/) )         #
# | |      | || || || (___) |            / (_) (_       ___) /      | |    | |         #
# | | ____ | |(_)| ||  ___  |           (____   _)     (___ (       | |    | |         #
# | | \_  )| |   | || (   ) | Game           ) (           ) \      | |    | |         #
# | (___) || )   ( || )   ( | Master's       | |   _ /\___/  / _  __) (_ __) (_        #
# (_______)|/     \||/     \| Assistant      (_)  (_)\______/ (_) \____/ \____/        #
#                                                                                      #
########################################################################################
*/

//
// GMA Mapper Client with background I/O processing.
//
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"os"
	"os/user"
	"runtime"
	"strconv"
	"strings"

	"github.com/MadScienceZone/go-gma/v4/mapper"
	"github.com/MadScienceZone/go-gma/v4/util"
	"github.com/google/uuid"
	"github.com/visualfc/atk/tk"
)

//
// Auto-configure values
//
const (
	GMAMapperVersion    = "4.0.0"  // @@##@@
	GMAMapperFileFormat = 20       // @@##@@
	GMAMapperProtocol   = 400      // @@##@@
	GMAVersionNumber    = "4.3.11" // @@##@@
)

//
// Application holds the global settings and other context
// for the application generally.
//
type Application struct {
	// FontList holds all of the fonts we will be using (other than the default).
	// The user is allowed to customize this list, and all the rest of the code
	// will use those settings by looking up font info here.
	FontList map[string]tk.Font

	// Styles holds all the customizable style information.
	Styles DisplayStyle

	// Logger is whatever device or file we're writing logs to.
	Logger *log.Logger

	// Root is the Tk root window for the application.
	Root *tk.Window

	// Local controls over whether the map reports HP accurately
	// (server may override)
	BlurAll bool
	BlurPct int

	// Should we make the toolbar buttons larger?
	LargeButtons bool

	// List of PCs who are important enough to get on the main menu
	PCList []mapper.PlayerToken

	// If DebugLevel is 0, no extra debugging output will be made.
	// otherwise, increasing levels of output are generated for
	// increasing values of DebugLevel.

	DebugLevel int

	// Server contact information
	ServerHost      string
	ServerPort      int
	SCPServerHost   string
	SCPServerDest   string
	ServerUsername  string
	ServerPassword  string
	ServerMkdirPath string
	ProxyHost       string
	ProxyURL        string
	UpdateURL       string

	// Should we keep our toolbar visible regardless of instructions from the server?
	KeepTools bool

	// Optional guidelines to draw on the map
	MajorGuides, MinorGuides gridGuide

	// The module ID code in play
	ModuleID string

	// Local tool paths
	NcPath  string
	SCPPath string
	SSHPath string

	// Should we ignore chat messages?
	SuppressChat bool

	// Should we preload cached objects?
	CachePreload bool

	// Paths to files we use
	StyleFilename      string
	TranscriptFilename string

	// True if we're restarting after an upgrade
	upgradeNotice bool
}

type gridGuide struct {
	interval int
	offset   struct {
		x, y int
	}
}

func (g *gridGuide) Parse(s string) error {
	var err error

	f := strings.SplitN(s, "+", 2)
	g.interval, err = strconv.Atoi(f[0])
	g.offset.x = 0
	g.offset.y = 0

	if err != nil {
		return err
	}

	if len(f) > 1 {
		ff := strings.SplitN(f[1], ":", 2)
		g.offset.x, err = strconv.Atoi(ff[0])
		if err != nil {
			return err
		}
		if len(ff) > 1 {
			g.offset.y, err = strconv.Atoi(ff[1])
			if err != nil {
				return err
			}
		} else {
			g.offset.y = g.offset.x
		}
	}
	return nil
}

//
// addFont defines a font to be used by the application and assigns it a name
// as the key of the FontList map.
//
func (a *Application) addFont(name, family string, size int, bold bool, ital bool) {
	var attrs []*tk.FontAttr

	if bold {
		attrs = append(attrs, tk.FontAttrBold())
	}
	if ital {
		attrs = append(attrs, tk.FontAttrItalic())
	}

	f := tk.NewUserFont(family, size, attrs...)
	if f == nil {
		a.Logger.Printf("unable to create %v %v font as \"%s\"", family, size, name)
	} else {
		a.FontList[name] = f
	}
}

func aboutMapper() {
	tk.MessageBox(nil, "About Mapper", fmt.Sprintf("GMA Mapper Client, Version %v, for GMA %v.", GMAMapperVersion, GMAVersionNumber),
		fmt.Sprintf("Copyright © Steve Willoughby, Aloha, Oregon, USA. All Rights Reserved. Distributed under the terms and conditions of the 3-Clause BSD License.\n\nThis client supports file format %v and server protocol %v.", GMAMapperFileFormat, GMAMapperProtocol), "ok",
		tk.MessageBoxIconInfo, tk.MessageBoxTypeOk)
}

func helpDice(a Application) {
	w := tk.NewWindow()
	w.SetTitle("Chat/Dice Roller Information")
	text := tk.NewText(w)
	text.SetTabWordProcessorStyle(false)
	if err := text.SetTabStops("5c"); err != nil {
		a.Logger.Printf("error setting tab stops: %v", err)
	}

	//
	// define type styles
	//
	for _, tagInfo := range []struct {
		tag   string
		font  string
		attrs []tk.TextTagAttr
	}{
		{"h1", "Tf14", []tk.TextTagAttr{tk.TextTagAttrJustify(tk.JustifyCenter)}},
		{"p", "Nf12", []tk.TextTagAttr{tk.TextTagAttrWrapMode(tk.LineWrapWord)}},
		{"i", "If12", []tk.TextTagAttr{tk.TextTagAttrWrapMode(tk.LineWrapWord)}},
		{"b", "Cf12", []tk.TextTagAttr{tk.TextTagAttrWrapMode(tk.LineWrapWord)}},
	} {
		at := append(tagInfo.attrs, tk.TextTagAttrFont(a.FontList[tagInfo.font]))
		if err := text.TagConfigure(tagInfo.tag, at...); err != nil {
			a.Logger.Printf("error defining text tag \"%s\": %v", tagInfo.tag, err)
		}
	}

	//
	// scrollbars
	//
	sb := tk.NewScrollBar(w, tk.Vertical)
	if err := sb.OnCommandEx(text.SetYViewArgs); err != nil {
		a.Logger.Printf("error setting scrollbar for syntax help window: %v", err)
	}
	if err := text.OnYScrollEx(sb.SetScrollArgs); err != nil {
		a.Logger.Printf("error setting scrollbar for syntax help window: %v", err)
	}
	grid := tk.NewGridLayout(w)
	if err := grid.AddWidgetEx(text, 0, 0, 1, 1, tk.StickyAll); err != nil {
		a.Logger.Printf("error setting layout for syntax help window: %v", err)
	}
	if err := grid.AddWidgetEx(sb, 0, 1, 1, 1, tk.StickyAll); err != nil {
		a.Logger.Printf("error setting layout for syntax help window: %v", err)
	}
	tk.GridRowIndex(grid, 0, tk.GridIndexAttrWeight(1))
	tk.GridColumnIndex(grid, 0, tk.GridIndexAttrWeight(1))
	w.ShowNormal()

	//
	// The text contents of the window. This is a sequence of lines.
	// Each line is a tuple of (tag, text) where tag is one of the defined type styles
	// (see above).
	//
	for _, line := range [][]struct {
		style, text string
	}{
		{{"h1", "Chat Window"}},
		{{"p", ""}},
		{{"p", "Select the recipient(s) to whom you wish to send a message, or select “To all” to send a global message to everyone. If you select one person, the message will be private to them. If you select another person, they will be "}, {"i", "added to "}, {"p", "the conversation, so the message goes to all of them. Selecting “all” will clear the recipient selection. The message is sent when you press Return in the entry field."}},
		{{"p", ""}},
		{{"h1", "Die Roller Syntax"}},
		{{"p", ""}},
		{{"p", "To roll dice, select the recipient(s) who can see the roll using the chat controls, type the die description in the ‘Roll’ field and press Return. To re-roll a recent die roll, just click the die button next to that roll in the ‘Recent’ list. Similarly to roll a saved ‘Preset’."}},
		{{"p", ""}},
		{{"p", "General syntax: ["}, {"i", "name"}, {"b", "="}, {"p", "] ["}, {"i", "qty"}, {"p", " ["}, {"b", "/"}, {"i", "div"}, {"p", "]]"}, {"b", " d "}, {"i", "sides"}, {"p", " ["}, {"b", "best"}, {"p", "|"}, {"b", "worst of "}, {"i", "n"}, {"p", "]  [...] ["}, {"b", "| "}, {"i", "modifiers"}, {"p", "]"}},
		{{"p", ""}},
		{{"p", "(The [square brackets] indicate optional values; they are not literally part of the expression syntax.)"}},
		{{"p", ""}},
		{{"p", "This will roll "}, {"i", "qty"}, {"p", " dice, each of which has the specified number of "}, {"i", "sides"}, {"p", " (i.e., each generates a number between 1 and "}, {"i", "sides"}, {"p", ", inclusive.) The result is divided by "}, {"i", "div"}, {"p", " (but in no case will the result be less than 1). Finally, any "}, {"i", "bonus"}, {"p", " (positive or negative) is added to the result. If "}, {"i", "factor"}, {"p", " is specified, the final result is multiplied by that amount."}},
		{{"p", ""}},
		{{"p", "As a special case, "}, {"i", "sides"}, {"p", " may be the character “"}, {"b", "%"}, {"p", "”, which means to roll percentile (d100) dice."}},
		{{"p", ""}},
		{{"p", "Where the [...] is shown above, you may place more die roll patterns or integer values, separated by "}, {"b", "+"}, {"p", ","}, {"b", " -"}, {"p", ","}, {"b", " *"}, {"p", ", or "}, {"b", "//"}, {"p", " to, respectively, add, subtract, multiply, or divide the following value from the total so far."}},
		{{"p", ""}},
		{{"p", "At the very end, you may place global modifiers separated from each other and from the die roll string with a vertical bar. These affect the outcome of the entire die roll in some way, by repeating the roll, confirming critical rolls, and so forth. The available global modifiers include:"}},
		{{"p", ""}},
		{{"b", "| c"}, {"p", "["}, {"i", "T"}, {"p", "]["}, {"b", "+"}, {"i", "B"}, {"p", "]\tThe roll (which must include a single die only) might be critical if it rolled a natural maximum die value (or at least "}, {"i", "T"}, {"p", " if specified). In this case, the entire roll will be repeated with the optional bonus (or penalty, if a - is used instead of a +) of "}, {"i", "B"}, {"p", " added to the confirmation roll."}},
		{{"b", "| min "}, {"i", "N"}, {"p", "\tThe result will be "}, {"i", "N"}, {"p", " or the result of the actual dice, whichever is greater."}},
		{{"b", "| max "}, {"i", "N"}, {"p", "\tThe result will be "}, {"i", "N"}, {"p", " or the result of the actual dice, whichever is less."}},
		{{"b", "| maximized"}, {"p", "\tAll dice will produce their maximum possible values rather than being random. (May also be given as "}, {"b", "!"}, {"p", ".)"}},
		{{"b", "| repeat "}, {"i", "N"}, {"p", "\tRoll the expression "}, {"i", "N"}, {"p", " times, reporting that many separate results."}},
		{{"b", "| until "}, {"i", "N"}, {"p", "\tRoll the expression repeatedly (reporting each result) until the result is at least "}, {"i", "N"}, {"p", "."}},
		{{"b", "| dc "}, {"i", "N"}, {"p", "\tThis is a check against a difficulty class (DC) of "}, {"i", "N"}, {"p", ". This does not affect the roll, but will report back whether the roll satisfied the DC and by what margin."}},
		{{"b", "| sf "}, {"p", "["}, {"i", "success"}, {"p", "["}, {"b", "/"}, {"i", "fail"}, {"p", "]]\tThis roll (which must involve but a single die) indicates automatic success or failure on a natural 20 or 1 respectively (or whatever the maximum value of the die is, if not a d20). The optional "}, {"i", "success"}, {"p", " or "}, {"i", "fail"}, {"p", " labels are used in the report (or suitable defaults are used if these are not given)."}},
		{{"p", ""}},
		{{"p", "Examples:"}},
		{{"b", "d20"}, {"p", "\tRoll a 20-sided die."}},
		{{"b", "3d6"}, {"p", "\tRoll three 6-sided dice and add them together."}},
		{{"b", "15d6+15"}, {"p", "\tRoll 16 6-sided dice and add them together, addiing 15 to the result."}},
		{{"b", "1d10+5*10"}, {"p", "\tRoll a 10-sided die, add 5, then multiply the result by 10."}},
		{{"b", "1/2d6"}, {"p", "\tRoll a 6-sided die, then divide the result by 2 (i.e., roll 1/2 of a d6)."}},
		{{"b", "2d10+3d6+12"}, {"p", "\tRoll 2d10, 3d6, add them plus 12 and report the result."}},
		{{"b", "d20+15|c"}, {"p", "\tRoll 1d20, add 15 and report the result. Additionally, if the d20 rolled a natural 20, roll 1d20+15 again and report that result."}},
		{{"b", "d20+15|c19+2"}, {"p", "\tRoll 1d20, add 15 and report the result. Additionally, if the d20 rolled a natural 19 or 20, roll 1d20+15+2 and report that result."}},
		{{"b", "d%"}, {"p", "\tRoll a percentile die, generating a number from 1-100."}},
		{{"b", "40%"}, {"p", "\tThis is an additional way to roll percentile dice, by specifying the probability of a successful outcome. In this example, the roll should be successful 40% of the time. The report will include the die roll and whether it was successful or not."}},
		{{"b", "40%"}, {"i", "label"}, {"p", "\tAs above, but indicate the event outcome as a 40% chance of being “"}, {"i", "label"}, {"p", "” and 60% chance of “did not "}, {"i", "label"}, {"p", "”. Note that if "}, {"i", "label"}, {"p", " is “hit” then “miss” will be displayed rather than “did not hit” and vice versa."}},
		{{"b", "40%"}, {"i", "a"}, {"b", "/"}, {"i", "b"}, {"p", "\tAs above, but indicate the event outcome as a 40% chance of being “"}, {"i", "a"}, {"p", "” and 60% chance of “"}, {"i", "b"}, {"p", "”."}},
		{{"b", "d20+12|max20"}, {"p", "\tRolls a d20, adds 12, and reports the result or 20, whichever is smaller."}},
		{{"b", "1d20+2d12+2|max20"}, {"p", "\tRolls a d20, 2 12-sided dice, adds them together, adds 2 to the sum, then reports the result or 20, whichever is smaller."}},
		{{"p", ""}},
		{{"p", "You can’t use the "}, {"b", "c"}, {"p", "... modifier to ask for confirmation rolls if there was more than one die involved in your roll."}},
		{{"p", ""}},
		{{"h1", "Fancy Things"}},
		{{"p", ""}},
		{{"p", "You can put “"}, {"i", "name"}, {"b", "="}, {"p", "” in front of the entire expression to label it for what it represents. For example, “"}, {"b", "attack=d20+5 | c"}, {"p", "” rolls d20+5 (with confirmation check) but reports it along with the name “attack” to make it clear what the roll was for."}},
		{{"p", ""}},
		{{"p", "The "}, {"b", "best of"}, {"p", " pattern will cause the die preceding it to be rolled "}, {"i", "n"}, {"p", " times and the best of them taken. (Similarly, you can use “"}, {"b", "worst"}, {"p", "” in place of “"}, {"b", "best"}, {"p", "”.)"}},
		{{"p", ""}},
		{{"b", "d20 best of 2 + 12"}, {"p", "\tRolls 2 d20, takes the better of the 2, then adds 12."}},
		{{"p", ""}},
		{{"p", "A whole set of related rolls may be made using a permutation syntax. For example, say a full round attack for your character is done with modifiers +17, +12, and +7. This may be rolled all at once by giving the die roll as “"}, {"b", "d20+{17/12/7}"}, {"p", "”."}},
		{{"p", ""}},
		{{"p", "If you put some random text at the end of any die roll expression, it will be repeated in the output. You can use this to label things like energy damage in a die roll like “"}, {"b", "Damage = 1d12 + 1d6 fire + 2d6 sneak"}, {"p", "”."}},
		{{"p", ""}},
		{{"h1", "Presets"}},
		{{"p", ""}},
		{{"p", "Saving preset rolls to the server allows them to be available any time your client connects to it. Each preset is given a unique name. If another preset is added with the same name, it will replace the previous one."}},
		{{"p", "If a vertical bar ("}, {"b", "|"}, {"p", ") appears in the preset name, everything up to and including the bar is not displayed in the tool, but the sort order of the preset display is based on the entire name. This allows you to sort the entries in any arbitrary order without cluttering the display if you wish. This is most convenient if you save your presets to a file, edit them, and load them back again."}},
	} {
		for _, part := range line {
			text.AppendTextWithTag(part.text, part.style)
		}
		text.AppendText("\n")
	}
}

func okToExit() bool {
	answer, err := tk.MessageBox(nil, "Ok to quit?", "Is it ok to stop now?", "(more details...)", "cancel", tk.MessageBoxIconWarning, tk.MessageBoxTypeOkCancel)
	if err != nil {
		fmt.Printf("ERROR posting okToExit dialog: %v\n", err)
		return true
	}
	return answer == "ok"
}

//
// Command-line arguments (from the command line and/or config file)
// If we see a --config option then we'll populate our set of defaults
// from that first, then override with command-line options.
//

func setConfigDefaults() util.SimpleConfigurationData {
	cdata := util.NewSimpleConfigurationData()
	for _, v := range []struct {
		option, value string
	}{
		{"blur-all", "0"},
		{"blur-hp", "0"},
		{"button-size", "small"},
		{"character", ""},
		{"chat-history", "512"},
		{"curl-path", "/usr/bin/curl"},
		{"curl-url-base", "https://www.rag.com/gma/map"},
		{"dark", "0"},
		{"debug", "0"},
		{"guide", ""},
		{"host", ""},
		{"keep-tools", "0"},
		{"log", ""},
		{"major", ""},
		{"master", "0"},
		{"mkdir-path", "/bin/mkdir"},
		{"module", ""},
		{"nc-path", "/usr/bin/nc"},
		{"no-blur-all", "0"},
		{"no-chat", "0"},
		{"password", ""},
		{"port", "2323"},
		{"preload", "0"},
		{"proxy-host", ""},
		{"proxy-url", ""},
		{"scp-dest", ""},
		{"scp-path", "/usr/bin/scp"},
		{"scp-server", ""},
		{"ssh-path", "/usr/bin/ssh"},
		{"style", "~/.gma/mapper/style.conf"},
		{"transcript", ""},
		{"update-url", ""},
		{"upgrade-notice", "0"},
		{"username", "__unknown__"},
	} {
		cdata.Set(v.option, v.value)
	}
	if u, err := user.Current(); err == nil {
		cdata.Set("username", u.Username)
	}
	if home, err := os.UserHomeDir(); err == nil {
		cdata.Set("log", strings.Join([]string{home, ".gma", "mapper", "logs", fmt.Sprintf("mapper.%d.log", os.Getpid())}, string(os.PathSeparator)))
	}
	return cdata
}

type multiOptionString []string

func (o *multiOptionString) String() string {
	if o == nil {
		return ""
	}
	return strings.Join(*o, ",")
}

func (o *multiOptionString) Set(s string) error {
	*o = append(*o, s)
	return nil
}

type optionCount int

func (o *optionCount) String() string {
	if o == nil {
		return "0"
	}
	return strconv.Itoa(int(*o))
}

func (o *optionCount) Set(s string) error {
	*o++
	return nil
}

func (a *Application) LoadDisplayStyle() error {
	a.Styles = DefaultDisplayStyle()
	if a.StyleFilename != "" {
		sfile, err := os.Open(a.StyleFilename)
		if err != nil {
			a.Logger.Printf("warning: unable to open style configuration file \"%s\": %v", a.StyleFilename, err)
		} else {
			defer func() {
				if err := sfile.Close(); err != nil {
					a.Logger.Printf("warning: unable to close \"%s\": %v", a.StyleFilename, err)
				}
			}()

			if err := json.NewDecoder(sfile).Decode(&a.Styles); err != nil {
				a.Logger.Printf("warning: unable to read style configuration from \"%s\": %v", a.StyleFilename, err)
			}
		}
	}
	return nil
}

func (a *Application) DefineDeclaredFonts() {
	a.FontList = make(map[string]tk.Font)

	for fName, fData := range a.Styles.Fonts {
		var attrs []*tk.FontAttr
		if fData.Weight == mapper.FontWeightBold {
			attrs = append(attrs, tk.FontAttrBold())
		}
		if fData.Slant == mapper.FontSlantItalic {
			attrs = append(attrs, tk.FontAttrItalic())
		}
		a.Logger.Printf("creating \"%s\" family %q, size %q, attrs %q", fName, fData.Family, int(fData.Size), attrs)

		a.FontList[fName] = tk.NewUserFont(fData.Family, int(fData.Size), attrs...)
	}
}

func (a *Application) GetAppOptions() error {
	var defaultConfigPath string
	var charList multiOptionString
	var debugLevel optionCount
	var err error

	cdata := setConfigDefaults()

	// no-blur-all should be moved to blur-all with a false value so we just have one
	// variable to indicate the desired status. we have both keywords due to legacy
	// semantics for boolean options.
	//
	// Thus, in the config file setting
	//    blur-all=0
	// and
	//    no-blur-all
	// are equivalent now and we'll only look at blur-all's value.
	if cdata.GetBoolDefault("no-blur-all", false) {
		cdata.Set("blur-all", "0")
	}

	if home, err := os.UserHomeDir(); err == nil {
		defaultConfigPath = strings.Join([]string{home, ".gma", "mapper", "mapper.conf"}, string(os.PathSeparator))
	}

	var noAnimate = flag.Bool("no-animate", false, "Don't animate element drawing on the map")
	flag.BoolVar(noAnimate, "a", false, "same as -no-animate")
	var animate = flag.Bool("animate", false, "Animate element drawing on the map")
	flag.BoolVar(animate, "A", false, "same as -animate")
	var blurAll = flag.Bool("blur-all", false, "Show approximate hit points for all creatures")
	flag.BoolVar(animate, "B", false, "same as -blur-all")
	var noBlurAll = flag.Bool("no-blur-all", false, "Show approximate hit points ONLY for non-players")
	var blurHP = flag.Int("blur-hp", 0, "Percentage of hit point blurring")
	flag.IntVar(blurHP, "b", 0, "same as -blur-hp")
	var logFile = flag.String("log", "", "Write log info to named file [default=stderr]")
	var configFile = flag.String("config", defaultConfigPath, "Read configuration options from file")
	flag.StringVar(configFile, "C", defaultConfigPath, "same as -config")
	flag.Var(&charList, "character", "Add PC to menu (value is name[:color], specify multiple times)")
	flag.Var(&charList, "c", "same as -character")
	flag.Var(&debugLevel, "debug", "Increment debugging level")
	flag.Var(&debugLevel, "D", "same as -debug")
	var darkMode = flag.Bool("dark", false, "Use dark mode")
	flag.BoolVar(darkMode, "d", false, "same as -dark")
	var host = flag.String("host", "", "Map server hostname")
	flag.StringVar(host, "h", "", "same as -host")
	var password = flag.String("password", "", "Server login password")
	flag.StringVar(password, "P", "", "same as -password")
	var port = flag.Int("port", 2323, "Server TCP port")
	flag.IntVar(port, "p", 2323, "same as -port")
	var guide = flag.String("guide", "", "minor guideline (as interval[+x:y])")
	flag.StringVar(guide, "g", "", "same as -guide")
	var major = flag.String("major", "", "major guideline (as interval[+x:y])")
	flag.StringVar(major, "G", "", "same as -major")
	var module = flag.String("module", "", "Module ID")
	flag.StringVar(module, "M", "", "same as -module")
	var DEPRECATEDmaster = flag.Bool("master", false, "same as -keep-tools (deprecated name)")
	flag.BoolVar(DEPRECATEDmaster, "m", false, "same as -master")
	var keepTools = flag.Bool("keep-tools", false, "Keep toolbar on unconditionally")
	flag.BoolVar(keepTools, "k", false, "same as -keep-tools")
	var noChat = flag.Bool("no-chat", false, "Suppress receipt of chat messages")
	flag.BoolVar(noChat, "n", false, "same as -no-chat")
	var style = flag.String("style", "", "Style settings filename")
	flag.StringVar(style, "s", "", "same as -style")
	var transcript = flag.String("transcript", "", "Chat transcript save filename")
	flag.StringVar(transcript, "t", "", "same as -transcript")
	var username = flag.String("username", "", "Name to use on the game server (default is local username)")
	flag.StringVar(username, "u", "", "same as -username")
	var proxyURL = flag.String("proxy-url", "", "Proxy URL for curl access to server")
	flag.StringVar(proxyURL, "x", "", "same as -proxy-url")
	var proxyHost = flag.String("proxy-host", "", "Proxy hostname for ssh access to server")
	flag.StringVar(proxyHost, "X", "", "same as -proxy-host")
	var preload = flag.Bool("preload", false, "Preload map elements from cache")
	flag.BoolVar(preload, "l", false, "same as -preload")
	var buttonSize = flag.String("button-size", "small", "Size for toolbar buttons")
	var chatHistory = flag.Int("chat-history", 512, "Number of historical chat messages to keep")
	var curlPath = flag.String("curl-path", "", "Path to curl program locally")
	var curlURLBase = flag.String("curl-url-path", "", "Base URL to fetch artifacts via curl")
	var mkdirPath = flag.String("mkdir-path", "", "Path to mkdir on server")
	var ncPath = flag.String("nc-path", "", "Path to nc program locally")
	var scpPath = flag.String("scp-path", "", "Path to scp program locally")
	var scpDest = flag.String("scp-dest", "", "Path to server data area")
	var scpServer = flag.String("scp-server", "", "Hostname of server for scp transfers")
	var sshPath = flag.String("ssh-path", "", "Path to ssh program locally")
	var generateStyleConfig = flag.String("generate-style-config", "", "Generate a new style config file, writing to the named file")
	var generateConfig = flag.String("generate-config", "", "Generate a new mapper config file, writing to the named file")
	var updateURL = flag.String("update-url", "", "URL for program updates")
	var upgradeNotice = flag.Bool("upgrade-notice", false, "(for internal use only)")

	flag.Parse()

	if *configFile != "" {
		cfile, err := os.Open(*configFile)
		if err != nil {
			a.Logger.Printf("warning: unable to open configuration file \"%s\": %v", *configFile, err)
		} else {
			if err := util.UpdateSimpleConfig(cfile, cdata); err != nil {
				a.Logger.Printf("warning: unable to parse configuration file \"%s\": %v", *configFile, err)
			}
		}
	}

	if err := cdata.Override(
		util.OverrideString("log", *logFile),
	); err != nil {
		a.Logger.Fatalf("error handling command-line arguments: %v", err)
	}

	if *logFile != "" {
		f, err := os.OpenFile(*logFile, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
		if err != nil {
			a.Logger.Printf("unable to open log file \"%s\": %v", *logFile, err)
		} else {
			a.Logger.SetOutput(f)
		}
	}

	if *animate || *noAnimate {
		a.Logger.Printf("--animate/--no-animate options deprecated (ignored)")
	}

	if err := cdata.Override(
		util.OverrideBool("animate", *animate),
		util.OverrideBool("no-animate", *noAnimate),
		util.OverrideBoolWithNegation("blur-all", *blurAll, *noBlurAll),
		util.OverrideInt("blur-hp", *blurHP),
		util.OverrideString("button-size", *buttonSize),
		util.OverrideString("character", charList.String()),
		util.OverrideInt("chat-history", *chatHistory),
		util.OverrideString("curl-path", *curlPath),
		util.OverrideString("curl-url-base", *curlURLBase),
		util.OverrideBool("dark", *darkMode),
		util.OverrideInt("debug", int(debugLevel)),
		util.OverrideString("guide", *guide),
		util.OverrideString("host", *host),
		util.OverrideBool("keep-tools", *keepTools),
		util.OverrideString("major", *major),
		util.OverrideBool("master", *DEPRECATEDmaster),
		util.OverrideString("mkdir-path", *mkdirPath),
		util.OverrideString("module", *module),
		util.OverrideString("nc-path", *ncPath),
		util.OverrideBool("no-chat", *noChat),
		util.OverrideString("password", *password),
		util.OverrideInt("port", *port),
		util.OverrideBool("preload", *preload),
		util.OverrideString("proxy-host", *proxyHost),
		util.OverrideString("proxy-url", *proxyURL),
		util.OverrideString("scp-dest", *scpDest),
		util.OverrideString("scp-path", *scpPath),
		util.OverrideString("scp-server", *scpServer),
		util.OverrideString("ssh-path", *sshPath),
		util.OverrideString("style", *style),
		util.OverrideString("transcript", *transcript),
		util.OverrideString("update-url", *updateURL),
		util.OverrideBool("upgrade-notice", *upgradeNotice),
		util.OverrideString("username", *username),
	); err != nil {
		a.Logger.Fatalf("error handling command-line arguments: %v", err)
	}

	if *generateStyleConfig != "" {
		if err := GenerateStyleConfig(*a, *generateStyleConfig); err != nil {
			a.Logger.Fatalf("error generating style configuration file: %v", err)
		}
	}

	if *generateConfig != "" {
		if err := GenerateConfig(*a, *generateConfig); err != nil {
			a.Logger.Fatalf("error generating configuration file: %v", err)
		}
	}

	if *generateStyleConfig != "" || *generateConfig != "" {
		os.Exit(0)
	}

	if cdata.GetBoolDefault("no-animate", false) || cdata.GetBoolDefault("animate", false) {
		a.Logger.Printf("warning: --animate and --no-animate are deprecated (ignored)")
	}

	if cdata.GetBoolDefault("master", false) {
		if cdata.GetBoolDefault("keep-tools", false) {
			a.Logger.Printf("warning: --master deprecated (you also specified --keep-tools; just remove --master)")
		} else {
			a.Logger.Printf("warning: --master deprecated (use --keep-tools instead)")
			cdata.Set("keep-tools", "1")
		}
	}

	// now cdata has our defaults + config file data + command-line options
	// so we can just validate that list and act on it.

	for _, v := range []struct {
		dst *string
		key string
	}{
		{&a.ServerHost, "host"},
		{&a.ServerMkdirPath, "mkdir-path"},
		{&a.ModuleID, "module"},
		{&a.NcPath, "nc-path"},
		{&a.ServerPassword, "password"},
		{&a.ProxyHost, "proxy-host"},
		{&a.ProxyURL, "proxy-url"},
		{&a.SCPServerDest, "scp-dest"},
		{&a.SCPPath, "scp-path"},
		{&a.SCPServerHost, "scp-server"},
		{&a.SSHPath, "ssh-path"},
		{&a.StyleFilename, "style"},
		{&a.TranscriptFilename, "transcript"},
		{&a.UpdateURL, "update-url"},
		{&a.ServerUsername, "username"},
	} {
		*v.dst, _ = cdata.GetDefault(v.key, "")
	}

	for _, v := range []struct {
		dst *bool
		key string
	}{
		{&a.BlurAll, "blur-all"},
		{&a.KeepTools, "keep-tools"},
		{&a.SuppressChat, "no-chat"},
		{&a.CachePreload, "preload"},
		{&a.upgradeNotice, "upgrade-notice"},
	} {
		*v.dst, err = cdata.GetBool(v.key)
		if err != nil {
			a.Logger.Fatalf("unable to set boolean option \"%s\": %v", v.key, err)
		}
	}

	for _, v := range []struct {
		dst *int
		key string
	}{
		{&a.BlurPct, "blur-hp"},
		{&a.DebugLevel, "debug"},
		{&a.ServerPort, "port"},
	} {
		*v.dst, err = cdata.GetInt(v.key)
		if err != nil {
			a.Logger.Fatalf("unable to set integer option \"%s\": %v", v.key, err)
		}
	}

	if a.BlurPct < 0 {
		a.BlurPct = 0
	}

	if a.BlurPct > 100 {
		a.BlurPct = 100
	}

	bs, _ := cdata.GetDefault("button-size", "small")
	switch bs {
	case "small":
		a.LargeButtons = false
	case "large":
		a.LargeButtons = true
	default:
		a.Logger.Printf("warning: -button-size=\"%s\" invalid (must be \"small\" or \"large\")", bs)
	}

	chars, _ := cdata.GetDefault("character", "")
	for _, ch := range strings.Split(chars, ",") {
		cparts := strings.Split(ch, ":")
		if len(cparts) == 1 {
			cparts = append(cparts, "blue")
		}
		if len(cparts) != 2 {
			a.Logger.Printf("warning: illegal character option value \"%s\"", ch)
			continue
		}
		newId, err := uuid.NewRandom()
		if err != nil {
			a.Logger.Printf("warning: unable to generate an ID for \"%s\": %v", ch, err)
			continue
		}

		a.PCList = append(a.PCList, mapper.PlayerToken{
			CreatureToken: mapper.CreatureToken{
				BaseMapObject: mapper.BaseMapObject{
					ID: newId.String(),
				},
				CreatureType: mapper.CreatureTypePlayer,
				Name:         cparts[0],
				Color:        cparts[1],
				Size:         "M",
				Area:         "M",
			},
		})
	}

	g, ok := cdata.Get("guide")
	if ok && g != "" {
		if err := a.MinorGuides.Parse(g); err != nil {
			a.Logger.Printf("warning: can't understand minor guide spec \"%s\": %v", g, err)
		}
	}

	g, ok = cdata.Get("major")
	if ok && g != "" {
		if err := a.MajorGuides.Parse(g); err != nil {
			a.Logger.Printf("warning: can't understand major guide spec \"%s\": %v", g, err)
		}
	}

	return nil
}

func main() {
	// TODO read style config (setting fonts etc)
	mapApp := Application{
		FontList: make(map[string]tk.Font),
		Logger:   log.Default(),
	}
	mapApp.Logger.SetPrefix("mapper: ")
	mapApp.GetAppOptions()
	mapApp.LoadDisplayStyle()

	tk.MainLoop(func() {
		mapApp.DefineDeclaredFonts()
		//
		// Set up menus
		//
		if runtime.GOOS == "darwin" {
			//
			// On macos, use the application menu where possible
			//
			interp := tk.MainInterp()
			if interp == nil {
				mapApp.Logger.Fatal("no Tcl interpreter found")
			}
			_, err := interp.CreateCommand("::tk::mac::ShowPreferences", func(args []string) (string, error) {
				_, err := tk.MessageBox(nil, "Edit Preferences", "In this version of the mapper tool, editing preferences is done by modifying the GMA Mapper configuration file.", "", "ok", tk.MessageBoxIconInfo, tk.MessageBoxTypeOk)
				return "", err
			})
			if err != nil {
				mapApp.Logger.Fatalf("error creating MacOS ShowPreferences event hook: %v", err)
			}

			/*
				ret, err := interp.InvokeCommand(prefhook, []string{"Just", "Testing"})
				if err != nil {
					panic(err)
				}
				fmt.Printf("returned '%s'\n", ret)
			*/

			_, err = interp.CreateCommand("::tk::mac::Quit", func(args []string) (string, error) {
				fmt.Println("Exiting via mac menu")
				if okToExit() {
					tk.Quit()
				}
				return "", nil
			})
			if err != nil {
				mapApp.Logger.Fatalf("error creating MacOS Quit event hook: %v", err)
			}
		}

		/*
			tk.MainInterp().Eval("foo")
		*/

		mapApp.Root = tk.RootWindow()

		mapApp.Root.SetTitle("GMA Mapper")
		mapApp.Root.OnClose(func() bool {
			fmt.Printf("In OnClose\n")
			return okToExit()
		})

		menuBar := tk.NewMenu(mapApp.Root)
		fileMenu := tk.NewMenu(menuBar)
		editMenu := tk.NewMenu(menuBar)
		viewMenu := tk.NewMenu(menuBar)
		playMenu := tk.NewMenu(menuBar)
		helpMenu := tk.NewMenu(menuBar)

		fileMenu.AddAction(tk.NewActionEx("Load Map File...", func() {}))
		fileMenu.AddAction(tk.NewActionEx("Merge Map File...", func() {}))
		fileMenu.AddAction(tk.NewActionEx("Save Map File...", func() {}))
		if runtime.GOOS != "darwin" {
			fileMenu.AddSeparator()
			fileMenu.AddAction(tk.NewActionEx("Exit", func() {
				if okToExit() {
					tk.Quit()
				}
			}))
		}

		editMenu.AddAction(tk.NewActionEx("Normal Play Mode", func() {}))
		editMenu.AddSeparator()
		editMenu.AddAction(tk.NewActionEx("Clear All Map Elements", func() {}))
		editMenu.AddAction(tk.NewActionEx("Clear All Monsters", func() {}))
		editMenu.AddAction(tk.NewActionEx("Clear All Players", func() {}))
		editMenu.AddAction(tk.NewActionEx("Clear All Creatures", func() {}))
		editMenu.AddAction(tk.NewActionEx("Clear All Objects", func() {}))
		editMenu.AddSeparator()
		editMenu.AddAction(tk.NewActionEx("Draw Lines", func() {}))
		editMenu.AddAction(tk.NewActionEx("Draw Rectangles", func() {}))
		editMenu.AddAction(tk.NewActionEx("Draw Polygons", func() {}))
		editMenu.AddAction(tk.NewActionEx("Draw Circles/Ellipses", func() {}))
		editMenu.AddAction(tk.NewActionEx("Draw Arcs", func() {}))
		editMenu.AddAction(tk.NewActionEx("Add Text...", func() {}))
		editMenu.AddAction(tk.NewActionEx("Remove Objects", func() {}))
		editMenu.AddAction(tk.NewActionEx("Move Objects", func() {}))
		editMenu.AddAction(tk.NewActionEx("Stamp Objects", func() {}))
		editMenu.AddSeparator()
		editMenu.AddAction(tk.NewActionEx("Toggle Fill/No-Fill", func() {}))
		editMenu.AddAction(tk.NewActionEx("Choose Fill Color...", func() {}))
		editMenu.AddAction(tk.NewActionEx("Choose Outline Color...", func() {}))
		editMenu.AddSeparator()
		editMenu.AddAction(tk.NewActionEx("Cycle Grid Snap", func() {}))
		editMenu.AddAction(tk.NewActionEx("Cycle Line Thickness", func() {}))
		editMenu.AddSeparator()
		editMenu.AddAction(tk.NewActionEx("Remove Elements from File...", func() {}))

		viewMenu.AddAction(tk.NewActionEx("Hide Toolbar", func() {}))
		viewMenu.AddAction(tk.NewActionEx("Toggle Grid", func() {}))
		viewMenu.AddAction(tk.NewActionEx("Toggle Health Stats", func() {}))
		viewMenu.AddSeparator()
		viewMenu.AddAction(tk.NewActionEx("Zoom In", func() {}))
		viewMenu.AddAction(tk.NewActionEx("Zoom Out", func() {}))
		viewMenu.AddAction(tk.NewActionEx("Restore Zoom", func() {}))
		viewMenu.AddSeparator()
		viewMenu.AddAction(tk.NewActionEx("Scroll to Visible Objects", func() {}))
		viewMenu.AddAction(tk.NewActionEx("Scroll Others' Views to Match Mine", func() {}))
		viewMenu.AddAction(tk.NewActionEx("Refresh Display", func() {}))

		playMenu.AddAction(tk.NewActionEx("Toggle Combat Mode", func() {}))
		playMenu.AddAction(tk.NewActionEx("Indicate Area of Effect", func() {}))
		playMenu.AddAction(tk.NewActionEx("Measure Distance Along Line(s)", func() {}))
		playMenu.AddAction(tk.NewActionEx("Show Chat/Die-roll Window", func() {}))
		playMenu.AddSeparator()
		playMenu.AddAction(tk.NewActionEx("Deselect All", func() {}))

		helpMenu.AddAction(tk.NewActionEx("About Mapper...", aboutMapper))
		helpMenu.AddAction(tk.NewActionEx("Die Roll Syntax...", func() { helpDice(mapApp) }))

		menuBar.AddSubMenu("File", fileMenu)
		menuBar.AddSubMenu("Edit", editMenu)
		menuBar.AddSubMenu("View", viewMenu)
		menuBar.AddSubMenu("Play", playMenu)
		menuBar.AddSubMenu("Help", helpMenu)
		mapApp.Root.SetMenu(menuBar)

		// Define our fonts
		mapApp.addFont("Tf14", "Helvetica", 14, true, false)
		mapApp.addFont("Nf12", "Times", 12, false, false)
		mapApp.addFont("If12", "Times", 12, false, true)
		mapApp.addFont("Tf12", "Helvetica", 12, true, false)
		mapApp.addFont("Cf12", "Courier", 12, true, false)

		mapApp.Root.ShowNormal()
	})
}

//
// DisplayStyle describes the user's preferences for how we
// display various things.
//
type DisplayStyleDetails map[string]DisplayStyleDetail

type DisplayStyleDetail struct {
	Font       string `json:",omitempty"`
	Color      string `json:",omitempty"`
	Background string `json:",omitempty"`
	Overstrike bool   `json:",omitempty"`
	Format     string `json:",omitempty"`
}

type DisplayStyleOptions struct {
	DarkStyle            DisplayStyleDetails
	LightStyle           DisplayStyleDetails
	CollapseDescriptions bool
}

type DisplayStyle struct {
	DieRollResults DisplayStyleOptions
	Fonts          map[string]mapper.TextFont
}

//
// DefaultDisplayStyle generates the built-in default style
// settings.
//
func DefaultDisplayStyle() DisplayStyle {
	return DisplayStyle{
		DieRollResults: DisplayStyleOptions{
			DarkStyle: DisplayStyleDetails{
				"best":       {Font: "If12", Format: " best of %s", Color: "#aaaaaa"},
				"bonus":      {Font: "Hf12", Color: "#fffb00"},
				"comment":    {Font: "If12", Color: "#fffb00"},
				"constant":   {Font: "Hf12"},
				"critlabel":  {Font: "If12", Format: "Confirm: ", Color: "#fffb00"},
				"critspec":   {Font: "If12", Color: "#fffb00"},
				"dc":         {Font: "If12", Format: "DC %s: ", Color: "#aaaaaa"},
				"diebonus":   {Font: "If12", Color: "red"},
				"diespec":    {Font: "Hf12"},
				"discarded":  {Font: "Hf12", Format: "{%s}", Overstrike: true, Color: "#aaaaaa"},
				"exceeded":   {Font: "If12", Format: "exceeded DC by %s", Color: "#00fa92"},
				"fail":       {Font: "Tf12", Format: "(%s)", Color: "red"},
				"from":       {Font: "Hf12", Color: "cyan"},
				"fullmax":    {Font: "Tf12", Format: "maximized", Color: "red"},
				"fullresult": {Font: "Tf16", Format: "%s ", Background: "blue"},
				"iteration":  {Font: "If12", Format: " (roll #%s)", Color: "#aaaaaa"},
				"label":      {Font: "If12", Format: " %s", Color: "cyan"},
				"max":        {Font: "If12", Format: "max %s", Color: "#aaaaaa"},
				"maximized":  {Font: "Tf12", Format: ">", Color: "red"},
				"maxroll":    {Font: "Tf12", Format: "{%s}", Color: "red"},
				"met":        {Font: "If12", Format: "successful", Color: "#00fa92"},
				"min":        {Font: "If12", Format: "min %s", Color: "#aaaaaa"},
				"moddelim":   {Font: "Hf12", Format: " | ", Color: "#fffb00"},
				"normal":     {Font: "Hf12"},
				"operator":   {Font: "Hf12"},
				"repeat":     {Font: "If12", Format: "repeat %s", Color: "#aaaaaa"},
				"result":     {Font: "Hf14"},
				"roll":       {Font: "Hf12", Format: "{%s}", Color: "#00fa92"},
				"separator":  {Font: "Hf12", Format: "="},
				"sf":         {Font: "If12", Color: "#aaaaaa"},
				"short":      {Font: "If12", Format: "missed DC by %s", Color: "red"},
				"success":    {Font: "Tf12", Color: "#00fa92"},
				"system":     {Font: "If10", Color: "cyan"},
				"title":      {Font: "Tf12", Format: "%s: "},
				"to":         {Font: "If12", Color: "red"},
				"until":      {Font: "If12", Color: "#aaaaaa"},
				"worst":      {Font: "If12", Color: "#aaaaaa"},
			},
			LightStyle: DisplayStyleDetails{
				"best":       {Font: "If12", Format: " best of %s", Color: "#888888"},
				"bonus":      {Font: "Hf12", Color: "#f05b00"},
				"comment":    {Font: "If12", Color: "#f05b00"},
				"constant":   {Font: "Hf12"},
				"critlabel":  {Font: "If12", Format: "Confirm: ", Color: "#f05b00"},
				"critspec":   {Font: "If12", Color: "#f05b00"},
				"dc":         {Font: "If12", Format: "DC %s: ", Color: "#888888"},
				"diebonus":   {Font: "If12", Color: "red"},
				"diespec":    {Font: "Hf12"},
				"discarded":  {Font: "Hf12", Format: "{%s}", Overstrike: true, Color: "#888888"},
				"exceeded":   {Font: "If12", Format: "exceeded DC by %s", Color: "green"},
				"fail":       {Font: "Tf12", Format: "(%s)", Color: "red"},
				"from":       {Font: "Hf12", Color: "blue"},
				"fullmax":    {Font: "Tf12", Format: "maximized", Color: "red"},
				"fullresult": {Font: "Tf16", Format: "%s ", Color: "#ffffff", Background: "blue"},
				"iteration":  {Font: "If12", Format: " (roll #%s)", Color: "#888888"},
				"label":      {Font: "If12", Format: " %s", Color: "blue"},
				"max":        {Font: "If12", Format: "max %s", Color: "#888888"},
				"maximized":  {Font: "Tf12", Format: ">", Color: "red"},
				"maxroll":    {Font: "Tf12", Format: "{%s}", Color: "red"},
				"met":        {Font: "If12", Format: "successful", Color: "green"},
				"min":        {Font: "If12", Format: "min %s", Color: "#888888"},
				"moddelim":   {Font: "Hf12", Format: " | ", Color: "#f05b00"},
				"normal":     {Font: "Hf12"},
				"operator":   {Font: "Hf12"},
				"repeat":     {Font: "If12", Format: "repeat %s", Color: "#888888"},
				"result":     {Font: "Hf14"},
				"roll":       {Font: "Hf12", Format: "{%s}", Color: "green"},
				"separator":  {Font: "Hf12", Format: "="},
				"sf":         {Font: "If12"},
				"short":      {Font: "If12", Format: "missed DC by %s", Color: "red"},
				"success":    {Font: "Tf12"},
				"system":     {Font: "If10", Color: "blue"},
				"title":      {Font: "Tf12", Format: "%s: "},
				"to":         {Font: "If12", Color: "red"},
				"until":      {Font: "If12", Color: "#888888"},
				"worst":      {Font: "If12", Color: "#888888"},
			},
			CollapseDescriptions: false,
		},
		Fonts: map[string]mapper.TextFont{
			"Tf16": {Family: "Helvetica", Size: 16, Weight: mapper.FontWeightBold},
			"Tf14": {Family: "Helvetica", Size: 14, Weight: mapper.FontWeightBold},
			"Tf12": {Family: "Helvetica", Size: 12, Weight: mapper.FontWeightBold},
			"Tf10": {Family: "Helvetica", Size: 10, Weight: mapper.FontWeightBold},
			"Tf8":  {Family: "Helvetica", Size: 8, Weight: mapper.FontWeightBold},
			"Hf14": {Family: "Helvetica", Size: 14},
			"Hf12": {Family: "Helvetica", Size: 12},
			"Hf10": {Family: "Helvetica", Size: 10},
			"If12": {Family: "Times", Size: 12, Slant: mapper.FontSlantItalic},
			"If10": {Family: "Times", Size: 10, Slant: mapper.FontSlantItalic},
			"Nf10": {Family: "Times", Size: 10},
			"Nf12": {Family: "Times", Size: 12},
			"Cf12": {Family: "Courier", Size: 12},
			"Cf10": {Family: "Courier", Size: 10},
		},
	}
}

// mapper.FontWeightType (-Normal, -Bold)
// mapper.FontSlantType (-Roman, -Italic)

//
// GenerateStyleConfig creates a default style configuration
// which may be used as a starting point for the user to
// customize the settings.
//
func GenerateStyleConfig(a Application, path string) error {
	file, err := os.Create(path)
	if err != nil {
		return fmt.Errorf("unable to create new style config file: %v", err)
	}
	defer func() {
		err := file.Close()
		if err != nil {
			a.Logger.Printf("error closing style config file \"%s\": %v", path, err)
		}
	}()

	dd := DefaultDisplayStyle()
	b, err := json.MarshalIndent(dd, "", "    ")
	if err != nil {
		return fmt.Errorf("unable to write new style config file: %v", err)
	}
	_, err = file.Write(b)
	if err != nil {
		return fmt.Errorf("unable to write new style config file: %v", err)
	}
	return nil
}

/*
[mapper_default_die_rolls]
;default_font= XXX set this to a font if you want it to be the default for all styles XXX
;bg_list_even= XXX set this to a color for even-numbered list rows
;bg_list_odd= XXX set this to a color for odd-numbered list rows}
*/

//
// GenerateConfig creates a default mapper config file which may be used
// as a starting point for the user to customize the application.
//
func GenerateConfig(a Application, path string) error {
	file, err := os.Create(path)
	if err != nil {
		return fmt.Errorf("unable to create new config file: %v", err)
	}
	defer func() {
		err := file.Close()
		if err != nil {
			a.Logger.Printf("error closing config file \"%s\": %v", path, err)
		}
	}()

	dd := setConfigDefaults()
	for _, v := range []struct {
		preamble, format, data string
	}{
		{`#------------------------------------------------------------------------------
# The following settings were automatically generated by the mapper client.
# This shows the full set of possible mapper configurations currently supported
# for this client, with the values that are built-in to the mapper client.
# You can delete any of these you don't want to change, so you get the built-
# in values by default. (That way if the built-in values change, you'll get
# the current ones instead of these.)
#
# Commented-out options are off by default. Un-comment them to enable them.
#------------------------------------------------------------------------------
#master DEPRECATED. Use keep-tools instead.
#animate DEPRECATED. Do not use.
#no-animate DEPRECATED. Do not use.
#
#------------------------------------------------------------------------
#                          Boolean flags
#
#Simply naming the option ("flagname") indicates "true", while leaving
#it out indicates "false" since all boolean flags are false by default.
#Also accepts "flagname=value" form with true values "1", "true", "yes",
#or "on" and false values "0", "false", "no", or "off".
#
#
# "blur" hit point reports for all creatures (vs just non-PCs). The
# option "no-blur-all" is equivalent to "blur-all=false".
#
#no-blur-all
#blur-all
#
# "dark" forces dark mode styling.
#dark
#
# "keep-tools" tells the mapper to keep its toolbar on regardless of
# the server's instructions.
#keep-tools
#
# "no-chat" suppresses reception of chat messages and die-roll results.
#no-chat
#
# "preload" causes the mapper to load up images and other elements from
# cache upon startup.
#preload
# 
#------------------------------------------------------------------------
#                           String/Int flags
#
# "blur-hp" indicates how much to "blur" hit point reporting with 0 being
# to report true values, 10 to report in increments of 10%, etc.
#blur-hp=0
#
# "button-size" may be "small" or "large" and controls toolbar buttons.
#button-size=small
#
# "character" adds a PC to the main menu. This may be specified multiple
# times (one for each character) and/or multiple characters given by
# separating them with commas. Each character is a name, optionally
# followed by a colon and color name, e.g.:
#     character=Alice
#     character=Bob:green
#     character=Charlie,Daria:blue,Eärendil:#88ffaa
#character=NAME:COLOR
#
# "chat-history" gives the number of old chat messages to retain.
`, "#chat-history=%s", dd["chat-history"]},
		{`#
# "debug" enables a level of debugging output. The greater the number
# the more verbose the output.
#debug=0
#
# "guide" adds minor guidelines:
#    guide=N     draws every N grid lines in a different color
#    guide=N+O   ...but also adjusts those lines O units right and down
#    guide=N+X:Y ...but also adjusts those lines X units right and Y down
#guide=
#
# "host" names the server hostname
#host=example.com
#
# "major" is like "guide" but adds major guidelines.
#major=
#
# "mkdir-path" gives the path ON THE SERVER of the mkdir command.
`, "#mkdir-path=%s", dd["mkdir-path"]},
		{`#
# "module" gives the module ID code currently in play.
#module=NAME
#
# "nc-path" gives the path ON THE CLIENT of the nc command.
`, "#nc-path=%s", dd["nc-path"]},
		{`#
# "password" is the password to use when logging in to the server.
#password=
#
# "port" is the TCP port number on the server to use.
`, "#port=%s", dd["port"]},
		{`#
# "proxy-host" specifies the SOCKS proxy to use when sending files TO
# the server.
#proxy-host=proxy.example.com:1080
#
# "proxy-url" specifies the parameters needed to connect to a SOCKS
# proxy when fetching image files FROM the server.
#proxy-url=https://proxy.example.org:1080
#
# "scp-dest" names the destination top-level directory when sending
# files TO the server.
#scp-dest=/var/www/data/gma
#
# "scp-path" is the location of the scp program on the client.
`, "#scp-path=%s", dd["scp-path"]},
		{`#
# "scp-server" is the hostname of the server to use when sending files
# TO the server.
#scp-server=example.com
#
# "ssh-path" is the location of the ssh program on the client.
`, "#ssh-path=%s", dd["ssh-path"]},
		{`#
# "style" names a style configuration file used to customize the look
# and feel of the client. Generate a default one by running the mapper
# with the --generate-style-config=PATH option.
#style=
#
# "transcript" names a file in which to record a transcript of the
# chat messages received. This path may include formatting tokens
# as documented in mapper(6), e.g., %m-%d-%y for the month-date-year
# value.
#transcript=
#
# "update-url" gives the base URL to use when downloading available
# software updates. This value should be given to you by your GM or
# whomever is setting up the game server and putting software there
# for you to download.
#update-url=
#
# "username" is the desired name you want to sign on to the server with.
`, "#username=%s", dd["username"]},
	} {
		if _, err := file.WriteString(v.preamble); err != nil {
			return err
		}
		if _, err := file.WriteString(fmt.Sprintf(v.format+"\n", v.data)); err != nil {
			return err
		}
	}
	return nil
}

//
// @[00]@| GMA 4.3.11
// @[01]@|
// @[10]@| Copyright © 1992–2022 by Steven L. Willoughby (AKA MadScienceZone)
// @[11]@| steve@madscience.zone (previously AKA Software Alchemy),
// @[12]@| Aloha, Oregon, USA. All Rights Reserved.
// @[13]@| Distributed under the terms and conditions of the BSD-3-Clause
// @[14]@| License as described in the accompanying LICENSE file distributed
// @[15]@| with GMA.
// @[16]@|
// @[20]@| Redistribution and use in source and binary forms, with or without
// @[21]@| modification, are permitted provided that the following conditions
// @[22]@| are met:
// @[23]@| 1. Redistributions of source code must retain the above copyright
// @[24]@|    notice, this list of conditions and the following disclaimer.
// @[25]@| 2. Redistributions in binary form must reproduce the above copy-
// @[26]@|    right notice, this list of conditions and the following dis-
// @[27]@|    claimer in the documentation and/or other materials provided
// @[28]@|    with the distribution.
// @[29]@| 3. Neither the name of the copyright holder nor the names of its
// @[30]@|    contributors may be used to endorse or promote products derived
// @[31]@|    from this software without specific prior written permission.
// @[32]@|
// @[33]@| THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND
// @[34]@| CONTRIBUTORS “AS IS” AND ANY EXPRESS OR IMPLIED WARRANTIES,
// @[35]@| INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
// @[36]@| MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
// @[37]@| DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS
// @[38]@| BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY,
// @[39]@| OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
// @[40]@| PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
// @[41]@| PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// @[42]@| THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR
// @[43]@| TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF
// @[44]@| THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
// @[45]@| SUCH DAMAGE.
// @[46]@|
// @[50]@| This software is not intended for any use or application in which
// @[51]@| the safety of lives or property would be at risk due to failure or
// @[52]@| defect of the software.
