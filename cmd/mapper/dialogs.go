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
	"fmt"

	"github.com/MadScienceZone/atk/tk"
)

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
			if err := text.AppendTextWithTag(part.text, part.style); err != nil {
				a.Logger.Printf("warning: trying to add text with tag \"%s\": %v", part.style, err)
			}
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
