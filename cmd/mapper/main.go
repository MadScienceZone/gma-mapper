/*
########################################################################################
#  _______  _______  _______             ______         ___     __       _______       #
# (  ____ \(       )(  ___  ) Game      / ___  \       /   )   /  \     (  __   )      #
# | (    \/| () () || (   ) | Master's  \/   \  \     / /) |   \/) )    | (  )  |      #
# | |      | || || || (___) | Assistant    ___) /    / (_) (_    | |    | | /   |      #
# | | ____ | |(_)| ||  ___  |             (___ (    (____   _)   | |    | (/ /) |      #
# | | \_  )| |   | || (   ) |                 ) \        ) (     | |    |   / | |      #
# | (___) || )   ( || )   ( | Mapper    /\___/  / _      | |   __) (_ _ |  (__) |      #
# (_______)|/     \||/     \| Client    \______/ (_)     (_)   \____/(_)(_______)      #
#                                                                                      #
########################################################################################
*/

//
// GMA Mapper Client with background I/O processing.
//
package main

import (
	"fmt"
	"runtime"

	"github.com/visualfc/atk/tk"
)

//
// Auto-configure values
//
const (
	GMAMapperVersion    = "3.41.0" // @@##@@
	GMAMapperFileFormat = 20       // @@##@@
	GMAMapperProtocol   = 400      // @@##@@
	GMAVersionNumber    = "4.3.11" // @@##@@
)

func aboutMapper() {
	_, err := tk.MessageBox(nil, "About Mapper", fmt.Sprintf("GMA Mapper Client, Version %v, for GMA %v.", GMAMapperVersion, GMAVersionNumber),
		fmt.Sprintf("Copyright © Steve Willoughby, Aloha, Oregon, USA. All Rights Reserved. Distributed under the terms and conditions of the 3-Clause BSD License.\n\nThis client supports file format %v and server protocol %v.", GMAMapperFileFormat, GMAMapperProtocol), "ok",
		tk.MessageBoxIconInfo, tk.MessageBoxTypeOk)
	if err != nil {
		panic(err)
	}
}

func helpDice() {
	w := tk.NewWindow()
	w.SetTitle("Chat/Dice Roller Information")
	text := tk.NewText(w)
	text.SetTabWordProcessorStyle(true)
	if err := text.DefineTagHACK("h1", map[string]string{"justify": "center", "font": Tf14.Id()}); err != nil {
		panic(err)
	}
	if err := text.DefineTagHACK("p", map[string]string{"wrap": "word", "font": Nf12.Id()}); err != nil {
		panic(err)
	}
	if err := text.DefineTagHACK("b", map[string]string{"wrap": "word", "font": Cf12.Id()}); err != nil {
		panic(err)
	}
	if err := text.DefineTagHACK("i", map[string]string{"wrap": "word", "font": If12.Id()}); err != nil {
		panic(err)
	}
	grid := tk.NewGridLayout(w)
	grid.AddWidget(text, tk.GridAttrSticky(tk.StickyAll))
	w.ShowNormal()
	// grid [text] [sb]	-sticky news
	//
	// column 0 weight 1
	// row 0 weight 1
	// tag h1 -justify center -font Tf14
	// tag p -font Nf12 -wrap word
	// tag i -font If12 -wrap word
	// tag b -font Tf12 -wrap word

	for _, line := range [][]struct {
		style, text string
	}{
		{{"h1", "Chat Window"}},
		{{"p", ""}},
		{{"p", "Select the recipient(s) to whom you wish to send a message, or select \"To all\" to send a global message to everyone. If you select one person, the message will be private to them. If you select another person, they will be "},
			{"i", "added to"},
			{"p", "the conversation, so the message goes to all of them. Selecting \"all\" will clear the recipient selection. The message is sent when you press Return in the entry field."},
		},
		{{"p", ""}},
		{{"h1", "Die Roller Syntax"}},
		{{"p", ""}},
		{{"p", "To roll dice, select the recipient(s) who can see the roll using the chat controls, type the die description in the 'Roll' field and press Return. To re-roll a recent die roll, just click the die button next to that roll in the 'Recent' list. Similarly to roll a saved 'Preset'."}},
		{{"p", ""}},
		{{"p", "General syntax: ["},
			{"i", "name"},
			{"b", "="},
			{"p", "] ["},
			{"i", "qty"},
			{"p", " ["},
			{"b", "/"},
			{"i", "div"},
			{"p", "]]"},
			{"b", " d "},
			{"i", "sides"},
			{"p", " ["},
			{"b", "best|worst of "},
			{"i", "n"},
			{"p", "]  [...] ["},
			{"b", "| "},
			{"i", "modifiers"},
			{"p", "]"},
		},
		{{"p", ""}},
		{{"p", "(The [square brackets] indicate optional values; they are not literally part of the expression syntax.)"}},
		{{"p", ""}},
		{{"p", "This will roll "}, {"i", "qty"}, {"p", " dice, each of which has the specified number of "},
			{"i", "sides"}, {"p", " (i.e., each generates a number between 1 and "}, {"i", "sides"},
			{"p", ", inclusive.) The result is divided by "}, {"i", "div"},
			{"p", " (but in no case will the result be less than 1). Finally, any "}, {"i", "bonus"},
			{"p", " (positive or negative) is added to the result. If "}, {"i", "factor"},
			{"p", " is specified, the final result is multiplied by that amount."}},
		{{"p", ""}},
		{{"p", "As a special case, "}, {"i", "sides"}, {"p", " may be the character \""}, {"b", "%"},
			{"p", "\", which means to roll percentile (d100) dice."}},
		{{"p", ""}},
		{{"p", "Where the [...] is shown above, you may place more die roll patterns or integer values, separated by "},
			{"b", "+"},
			{"p", ","},
			{"b", " -"},
			{"p", ","},
			{"b", " *"},
			{"p", ", or "},
			{"b", "//"},
			{"p", " to, respectively, add, subtract, multiply, or divide the following value from the total so far."}},
		{{"p", ""}},
		{{"p", "At the very end, you may place global modifiers separated from each other and from the die roll string with a vertical bar. These affect the outcome of the entire die roll in some way, by repeating the roll, confirming critical rolls, and so forth. The available global modifiers include:"}},
		{{"p", ""}},
		{{"b", "| c"}, {"p", "["}, {"i", "T"}, {"p", "]["}, {"b", "+"}, {"i", "B"}, {"p", "]\t\tThe roll (which must include a single die only) might be critical if it rolled a natural maximum die value (or at least "},
			{"i", "T"}, {"p", " if specified). In this case, the entire roll will be repeated with the optional bonus (or penalty, if a - is used instead of a +) of "},
			{"i", "B"}, {"p", " added to the confirmation roll."}},
		{{"b", "| min "}, {"i", "N"}, {"p", "\t\tThe result will be "}, {"i", "N"}, {"p", " or the result of the actual dice, whichever is greater."}},
		{{"b", "| max "}, {"i", "N"}, {"p", "\t\tThe result will be "}, {"i", "N"}, {"p", " or the result of the actual dice, whichever is less."}},
		{{"b", "| maximized"}, {"p", "\t\tAll dice will produce their maximum possible values rather than being random. (May also be given as "},
			{"b", "!"}, {"p", ".)"}},
		{{"b", "| repeat "}, {"i", "N"}, {"p", "\t\tRoll the expression "}, {"i", "N"}, {"p", " times, reporting that many separate results."}},
		{{"b", "| until "}, {"i", "N"}, {"p", "\t\tRoll the expression repeatedly (reporting each result) until the result is at least "}, {"i", "N"}, {"p", "."}},
		{{"b", "| dc "}, {"i", "N"}, {"p", "\t\tThis is a check against a difficulty class (DC) of "}, {"i", "N"},
			{"p", ". This does not affect the roll, but will report back whether the roll satisfied the DC and by what margin."}},
		{{"b", "| sf "}, {"p", "["}, {"i", "success"}, {"p", "["}, {"b", "/"}, {"i", "fail"}, {"p", "]]\tThis roll (which must involve but a single die) indicates automatic success or failure on a natural 20 or 1 respectively (or whatever the maximum value of the die is, if not a d20). The optional "}, {"i", "success"}, {"p", " or "}, {"i", "fail"}, {"p", " labels are used in the report (or suitable defaults are used if these are not given)."}},
		{{"p", ""}},
		{{"p", "Examples:"}},
		{{"b", "d20"}, {"p", "\t\tRoll a 20-sided die."}},
		{{"b", "3d6"}, {"p", "\t\tRoll three 6-sided dice and add them together."}},
		{{"b", "15d6+15"}, {"p", "\tRoll 16 6-sided dice and add them together, addiing 15 to the result."}},
		{{"b", "1d10+5*10"}, {"p", "\tRoll a 10-sided die, add 5, then multiply the result by 10."}},
		{{"b", "1/2d6"}, {"p", "\t\tRoll a 6-sided die, then divide the result by 2 (i.e., roll 1/2 of a d6)."}},
		{{"b", "2d10+3d6+12"}, {"p", "\tRoll 2d10, 3d6, add them plus 12 and report the result."}},
		{{"b", "d20+15|c"}, {"p", "\tRoll 1d20, add 15 and report the result. Additionally, if the d20 rolled a natural 20, roll 1d20+15 again and report that result."}},
		{{"b", "d20+15|c19+2"}, {"p", "\tRoll 1d20, add 15 and report the result. Additionally, if the d20 rolled a natural 19 or 20, roll 1d20+15+2 and report that result."}},
		{{"b", "d%"}, {"p", "\t\tRoll a percentile die, generating a number from 1-100."}},
		{{"b", "40%"}, {"p", "\t\tThis is an additional way to roll percentile dice, by specifying the probability of a successful outcome. In this example, the roll should be successful 40% of the time. The report will include the die roll and whether it was successful or not."}},
		{{"b", "40%"}, {"i", "label"}, {"p", "\tAs above, but indicate the event outcome as a 40% chance of being \""}, {"i", "label"}, {"p", "\" and 60% chance of \"did not "}, {"i", "label"}, {"p", "\". Note that if "}, {"i", "label"}, {"p", " is \"hit\" then \"miss\" will be displayed rather than \"did not hit\" and vice versa."}},
		{{"b", "40%"}, {"i", "a"}, {"b", "/"}, {"i", "b"}, {"p", "\t\tAs above, but indicate the event outcome as a 40% chance of being \""}, {"i", "a"}, {"p", "\" and 60% chance of \""}, {"i", "b"}, {"p", "\"."}},
		{{"b", "d20+12|max20"}, {"p", "\tRolls a d20, adds 12, and reports the result or 20, whichever is smaller."}},
		{{"b", "1d20+2d12+2|max20"}, {"p", "\tRolls a d20, 2 12-sided dice, adds them together, adds 2 to the sum, then reports the result or 20, whichever is smaller."}},
		{{"p", ""}},
		{{"p", "You can't use the "}, {"b", "c"}, {"p", "... modifier to ask for confirmation rolls if there was more than one die involved in your roll."}},
		{{"p", ""}},
		{{"h1", "Fancy Things"}},
		{{"p", ""}},
		{{"p", "You can put \""}, {"i", "name"}, {"b", "="}, {"p", "\" in front of the entire expression to label it for what it represents. For example, \""},
			{"b", "attack=d20+5 | c"}, {"p", "\" rolls d20+5 (with confirmation check) but reports it along with the name \"attack\" to make it clear what the roll was for."}},
		{{"p", ""}},
		{{"p", "The "}, {"b", "best of"}, {"p", " pattern will cause the die preceding it to be rolled "}, {"i", "n"},
			{"p", " times and the best of them taken. (Similarly, you can use \""}, {"b", "worst"},
			{"p", "\" in place of \""}, {"b", "best"}, {"p", "\".)"}},
		{{"p", ""}},
		{{"b", "d20 best of 2 + 12"}, {"p", "\tRolls 2 d20, takes the better of the 2, then adds 12."}},
		{{"p", ""}},
		{{"p", "A whole set of related rolls may be made using a permutation syntax. For example, say a full round attack for your character is done with modifiers +17, +12, and +7. This may be rolled all at once by giving the die roll as \""}, {"b", "d20+{17/12/7}"}, {"p", "\"."}},
		{{"p", ""}},
		{{"p", "If you put some random text at the end of any die roll expression, it will be repeated in the output. You can use this to label things like energy damage in a die roll like \""},
			{"b", "Damage = 1d12 + 1d6 fire + 2d6 sneak"}, {"p", "\"."}},
		{{"p", ""}},
		{{"h1", "Presets"}},
		{{"p", ""}},
		{{"p", "Saving preset rolls to the server allows them to be available any time your client connects to it. Each preset is given a unique name. If another preset is added with the same name, it will replace the previous one."}},
		{{"p", "If a vertical bar ("}, {"b", "|"}, {"p", ") appears in the preset name, everything up to and including the bar is not displayed in the tool, but the sort order of the preset display is based on the entire name. This allows you to sort the entries in any arbitrary order without cluttering the display if you wish. This is most convenient if you save your presets to a file, edit them, and load them back again."}},
	} {
		for _, part := range line {
			//text.AppendText(fmt.Sprintf("<%s>%s", part.style, part.text))
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

func main() {
	tk.MainLoop(func() {
		//
		// Set up menus
		//
		if runtime.GOOS == "darwin" {
			//
			// On macos, use the application menu where possible
			//
			interp := tk.MainInterp()
			if interp == nil {
				panic("no interpreter")
			}
			_, err := interp.CreateCommand("::tk::mac::ShowPreferences", func(args []string) (string, error) {
				_, err := tk.MessageBox(nil, "Edit Preferences", "In this version of the mapper tool, editing preferences is done by modifying the GMA Mapper configuration file.", "", "ok", tk.MessageBoxIconInfo, tk.MessageBoxTypeOk)
				return "", err
			})
			if err != nil {
				panic(err)
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
				panic(err)
			}
		}

		tk.MainInterp().Eval("foo")

		root := tk.RootWindow()
		root.SetTitle("ATK Sample")
		root.OnClose(func() bool {
			fmt.Printf("In OnClose\n")
			return okToExit()
		})

		menuBar := tk.NewMenu(root)
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
		helpMenu.AddAction(tk.NewActionEx("Die Roll Syntax...", helpDice))

		menuBar.AddSubMenu("File", fileMenu)
		menuBar.AddSubMenu("Edit", editMenu)
		menuBar.AddSubMenu("View", viewMenu)
		menuBar.AddSubMenu("Play", playMenu)
		menuBar.AddSubMenu("Help", helpMenu)
		root.SetMenu(menuBar)

		// Define our fonts
		Tf14 = tk.NewUserFont("Helvetica", 14, tk.FontAttrBold())
		Nf12 = tk.NewUserFont("Times", 12)
		If12 = tk.NewUserFont("Times", 12, tk.FontAttrItalic())
		Tf12 = tk.NewUserFont("Helvetica", 12, tk.FontAttrBold())
		Cf12 = tk.NewUserFont("Courier", 12, tk.FontAttrBold())

		root.ShowNormal()
	})
}

var Tf14, Nf12, If12, Tf12, Cf12 tk.Font

// @[00]@| GMA 4.3.11
// @[01]@|
// @[10]@| Copyright © 1992–2021 by Steven L. Willoughby
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
