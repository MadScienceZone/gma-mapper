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

type Window struct {
	*tk.Window
}

func NewWindow() *Window {
	mw := &Window{tk.RootWindow()}
	lbl := tk.NewLabel(mw, "Hello ATK")
	btn := tk.NewButton(mw, "Quit")
	btn.OnCommand(func() {
		tk.Quit()
	})
	tk.NewVPackLayout(mw).AddWidgets(lbl, tk.NewLayoutSpacer(mw, 0, true), btn)
	mw.ResizeN(300, 200)
	return mw
}

func aboutMapper() {
	_, err := tk.MessageBox(nil, "About Mapper", fmt.Sprintf("GMA Mapper Client, Version %v, for GMA %v.", GMAMapperVersion, GMAVersionNumber),
		fmt.Sprintf("Copyright © Steve Willoughby, Aloha, Oregon, USA. All Rights Reserved. Distributed under the terms and conditions of the 3-Clause BSD License.\n\nThis client supports file format %v and server protocol %v.", GMAMapperFileFormat, GMAMapperProtocol), "ok",
		tk.MessageBoxIconInfo, tk.MessageBoxTypeOk)
	if err != nil {
		panic(err)
	}
}

func exitCheck() {
	// TODO look for unsaved changes
	tk.Quit()
}

func main() {
	tk.MainLoop(func() {
		root := tk.RootWindow()
		root.SetTitle("ATK Sample")

		menuBar := tk.NewMenu(root)
		fileMenu := tk.NewMenu(menuBar)
		editMenu := tk.NewMenu(menuBar)
		viewMenu := tk.NewMenu(menuBar)
		playMenu := tk.NewMenu(menuBar)
		helpMenu := tk.NewMenu(menuBar)

		fileMenu.AddAction(tk.NewActionEx("Load Map File...", func() {}))
		fileMenu.AddAction(tk.NewActionEx("Merge Map File...", func() {}))
		fileMenu.AddAction(tk.NewActionEx("Save Map File...", func() {}))
		fileMenu.AddSeparator()
		fileMenu.AddAction(tk.NewActionEx("Exit", exitCheck))

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

		menuBar.AddSubMenu("File", fileMenu)
		menuBar.AddSubMenu("Edit", editMenu)
		menuBar.AddSubMenu("View", viewMenu)
		menuBar.AddSubMenu("Play", playMenu)
		menuBar.AddSubMenu("Help", helpMenu)
		root.SetMenu(menuBar)

		root.ShowNormal()
	})
}

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
