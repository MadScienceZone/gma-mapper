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
	"crypto/md5"
	"encoding/base64"
	"errors"
	"fmt"
	"io/fs"
	"math"
	"os"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/MadScienceZone/atk/tk"
	"github.com/MadScienceZone/go-gma/v4/mapper"
	"github.com/google/uuid"
)

type MapWidget struct {
	Canvas *tk.Canvas
}

func NewMapWidget(a *Application, p *tk.Window) *MapWidget {
	w := MapWidget{
		Canvas: tk.NewCanvas(p),
	}
	w.Canvas.SetWidth(1000)
	w.Canvas.SetHeight(1400)

	grid := tk.NewGridLayout(p)
	if err := grid.AddWidgetEx(w.Canvas, 0, 0, 1, 1, tk.StickyAll); err != nil {
		a.Logger.Fatalf("error setting map canvas: %v", err)
	}
	tk.GridRowIndex(grid, 0, tk.GridIndexAttrWeight(1))
	tk.GridColumnIndex(grid, 0, tk.GridIndexAttrWeight(1))
	//c.SetScrollRegion(0, 0, 40000, 40000)
	// canw=1000 canh=1400 cansw=40000 cansh 40000
	// -height $canh -width $canw -scrollregion [0 0 $cansw $cansh] -xscrollcommand {.xs set} -yscrollcommand {.ys set}
	//grid [frame .toolbar] -sticky ew
	//grid [frame .toolbar2] -sticky ew
	//grid .c [scrollbar .ys -orient vertical -command {battleGridScroller .c yview}] -sticky news
	//grid [scrollbar .xs -orient horizontal -command {battleGridScroller .c xview}]  -sticky  ew
	//label .c.distanceLabel -textvariable DistanceLabelText
	//bind $canvas <Shift-1> "PingMarker $canvas %x %y"
	return &w
}

func (w *MapWidget) BattleGridLabels(gridColor string, iScale int) {
	// save scrollbar position to {x,y}{start,end}frac
	//c.Delete "x#label"
	//startPx := int(xStartFrac * cansw)
	//endPx := int(xEndFrac * cansw)
	//startGrid := CanvasToGrid(startPx)
	//endGrid := CanvasToGric(endPx)
	//yPx := int(yStartFrac * cansh)
	//for xBox := startGrid; xBox <= endGrid; xBox++ {
	// c.Create text GridToCanvas(xBox)+(iscale/2.0) yPx
	//	-tags x#label -anchor n -justify center -text LetterLabel(xBox) -fill gridColor
	//}
	// same but for y axis
}

// LetterLabel converts a numeric value (counting from 0) to an alphabetic form which
// counts A..Z then AA..AZ, BA..BZ, and so forth.
func LetterLabel(n int) string {
	l := ""
	for ; n >= 0; n = n/26 - 1 {
		l = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"[n%26:n%26+1] + l
	}
	return l
}

// SplitCreatureImageName takes a creature image name and breaks it into
// bare name and image name.
func SplitCreatureImageName(name string) (string, string) {
	parts := strings.SplitN(name, "=", 2)
	if len(parts) == 0 {
		return "", ""
	}
	if len(parts) == 1 {
		return parts[0], parts[0]
	}
	return parts[0], parts[1]
}

//
// NewID generates a new object ID. Currently this is a UUID expressed
// in hexadecimal (without punctuation) but this is not guaranteed to
// always be the case.
//
func NewID() string {
	return strings.ReplaceAll(uuid.New().String(), "-", "")
}

//
// TileID converts a base name and zoom factor into a unified tile ID string.
//
func TileID(name string, zoom float64) string {
	return fmt.Sprintf("%s:%g", name, zoom)
}

//
// CacheInfo determines if the given file exists in the cache, and returns information
// about that file.
//
func CacheInfo(path string) (CacheInfoDetails, error) {
	imagePattern := regexp.MustCompile(`^(.+)@([0-9.]+)\.gif$`)
	mapPattern := regexp.MustCompile(`^(.+)\.map$`)
	var info CacheInfoDetails
	var err error

	fileComponents := strings.Split(path, string(os.PathSeparator))
	if len(fileComponents) == 0 {
		return CacheInfoDetails{}, fmt.Errorf("empty pathname in cache search")
	}

	if fields := imagePattern.FindStringSubmatch(fileComponents[len(fileComponents)-1]); fields != nil {
		info.BaseName = fields[1]
		if info.Zoom, err = strconv.ParseFloat(fields[2], 64); err != nil {
			return CacheInfoDetails{}, fmt.Errorf("unable to parse zoom factor \"%s\" in path \"%s\": %v", fields[2], path, err)
		}
	} else if fields := mapPattern.FindStringSubmatch(fileComponents[len(fileComponents)-1]); fields != nil {
		info.BaseName = fields[1]
		info.Zoom = 1.0
	} else {
		return CacheInfoDetails{}, fmt.Errorf("unable to parse path \"%s\": %v", path, err)
	}

	sinfo, err := os.Stat(path)
	if err != nil {
		if !errors.Is(err, fs.ErrNotExist) {
			return CacheInfoDetails{}, err
		}
	} else {
		info.IsCached = true
		info.CacheAge = time.Since(sinfo.ModTime())
	}
	return info, nil
}

type CacheInfoDetails struct {
	IsCached bool
	CacheAge time.Duration
	BaseName string
	Zoom     float64
}

//
// CacheFilename takes a base name and zoom factor, and returns
// the full pathname for the cached version of that image file.
//
// This will be <CACHE_DIR>/_<X>/<NAME>@<ZOOM>.gif, where
// <CACHE_DIR> is the top level directory for our cache, and
// <X> is the 5th character of <NAME>.
//
func (a *Application) ImageCacheFilename(name string, zoom float64) string {
	// TODO on Windows, make sure the directory exists
	// TODO nativename?
	return strings.Join([]string{a.CacheDirName(), "_" + name[4:5], fmt.Sprintf("%s@%g.gif", name, zoom)}, string(os.PathSeparator))
}

func (a *Application) MapCacheFilename(name string) string {
	return strings.Join([]string{a.CacheDirName(), "_" + name[0:1], name + ".map"}, string(os.PathSeparator))
}

func (a *Application) CacheDirName() string {
	if a.cacheDir == "" {
		cache, err := os.UserCacheDir()
		if err != nil {
			home, err2 := os.UserHomeDir()
			if err2 != nil {
				a.Logger.Fatalf("unable to figure out where to write cache data (%v, %v)", err, err2)
			}
			a.cacheDir = strings.Join([]string{home, ".gma", "mapper", "cache"}, string(os.PathSeparator))
		} else {
			a.cacheDir = cache + string(os.PathSeparator) + "gma-mapper"
		}
	}
	return a.cacheDir
}

//
// BlurHP returns the blurred hit point total to be displayed to the players.
//
func (a *Application) BlurHP(maxHP, lethalWounds int, isPC bool) int {
	if (isPC && !a.BlurAll) || a.BlurPct <= 0 || maxHP <= lethalWounds {
		return maxHP - lethalWounds
	}

	mf := float64(maxHP) * (float64(a.BlurPct) / 100.0)
	return maxInt(1, int(math.Floor(float64(maxHP-lethalWounds)/mf)*mf))
}

func maxInt(a, b int) int {
	if a < b {
		return b
	}
	return a
}

//
// ReachMatrix returns combat threat area definitions
// for the given creature size category code (with upper-case
// letters for "tall" and lower-case for "wide" variants).
//
// Returns 4 values: <area>, <reach>, <matrix>, <error>
// Note that <matrix> may be nil if we don't have any threatened
// squares.
//
// When highlighting the threat zone explicitly (i.e., when it
// is that creature's turn in combat), the threatened squares
// are highlighted according to the values in the <matrix> value.
//
// When it's not the creature's turn, a less-cluttered view is
// used where we just draw a dashed line around the character to
// show the threat radius. This is <area> squares BEYOND the
// perimeter of the creature's token circumference normally, or
// <reach> squares if the creature has reach weapons.
//
// The <matrix> has these values:
//	0x00	not a threatened square
//  0x01	included in "reach" threat zone
//	0x02	included in "normal" threat zone
//	0x03	(i.e., 1|2) included in both zones
//
func ReachMatrix(sizeCode string) (int, int, [][]byte, error) {
	switch sizeCode {
	case "F", "f", "D", "d", "T", "t", "L0", "l0":
		return 0, 0, nil, nil

	case "1", "S", "s", "M", "m":
		return 1, 2, [][]byte{
			{1, 1, 1, 1, 1},
			{1, 2, 2, 2, 1},
			{1, 2, 2, 2, 1},
			{1, 2, 2, 2, 1},
			{1, 1, 1, 1, 1},
		}, nil

	case "l":
		return 1, 2, [][]byte{
			{1, 1, 1, 1, 1, 1},
			{1, 2, 2, 2, 2, 1},
			{1, 2, 2, 2, 2, 1},
			{1, 2, 2, 2, 2, 1},
			{1, 2, 2, 2, 2, 1},
			{1, 1, 1, 1, 1, 1},
		}, nil

	case "2", "L":
		return 2, 4, [][]byte{
			{0, 0, 0, 1, 1, 1, 1, 0, 0, 0},
			{0, 1, 1, 1, 1, 1, 1, 1, 1, 0},
			{0, 1, 3, 2, 2, 2, 2, 3, 1, 0},
			{1, 1, 2, 2, 2, 2, 2, 2, 1, 1},
			{1, 1, 2, 2, 2, 2, 2, 2, 1, 1},
			{1, 1, 2, 2, 2, 2, 2, 2, 1, 1},
			{1, 1, 2, 2, 2, 2, 2, 2, 1, 1},
			{0, 1, 3, 2, 2, 2, 2, 3, 1, 0},
			{0, 1, 1, 1, 1, 1, 1, 1, 1, 0},
			{0, 0, 0, 1, 1, 1, 1, 0, 0, 0},
		}, nil

	case "m20", "M20":
		return 1, 4, [][]byte{
			{0, 0, 0, 1, 1, 1, 0, 0, 0},
			{0, 1, 1, 1, 1, 1, 1, 1, 0},
			{0, 1, 1, 1, 1, 1, 1, 1, 0},
			{1, 1, 1, 2, 2, 2, 1, 1, 1},
			{1, 1, 1, 2, 2, 2, 1, 1, 1},
			{1, 1, 1, 2, 2, 2, 1, 1, 1},
			{0, 1, 1, 1, 1, 1, 1, 1, 0},
			{0, 1, 1, 1, 1, 1, 1, 1, 0},
			{0, 0, 0, 1, 1, 1, 0, 0, 0},
		}, nil

	case "h":
		return 2, 4, [][]byte{
			{0, 0, 0, 1, 1, 1, 1, 1, 0, 0, 0},
			{0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0},
			{0, 1, 3, 2, 2, 2, 2, 2, 3, 1, 0},
			{1, 1, 2, 2, 2, 2, 2, 2, 2, 1, 1},
			{1, 1, 2, 2, 2, 2, 2, 2, 2, 1, 1},
			{1, 1, 2, 2, 2, 2, 2, 2, 2, 1, 1},
			{1, 1, 2, 2, 2, 2, 2, 2, 2, 1, 1},
			{1, 1, 2, 2, 2, 2, 2, 2, 2, 1, 1},
			{0, 1, 3, 2, 2, 2, 2, 2, 3, 1, 0},
			{0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0},
			{0, 0, 0, 1, 1, 1, 1, 1, 0, 0, 0},
		}, nil

	case "3", "H":
		return 3, 6, [][]byte{
			{0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0},
			{0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0},
			{0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0},
			{0, 1, 1, 1, 1, 2, 2, 2, 2, 2, 1, 1, 1, 1, 0},
			{0, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 0},
			{1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1},
			{1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1},
			{1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1},
			{1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1},
			{1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1},
			{0, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 0},
			{0, 1, 1, 1, 1, 2, 2, 2, 2, 2, 1, 1, 1, 1, 0},
			{0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0},
			{0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0},
			{0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0},
		}, nil

	case "G":
		return 4, 8, [][]byte{
			{0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0},
			{0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0},
			{0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0},
			{0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0},
			{0, 0, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 0, 0},
			{0, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 0},
			{0, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 0},
			{1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1},
			{1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1},
			{1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1},
			{1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1},
			{1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1},
			{1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1},
			{0, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 0},
			{0, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 0},
			{0, 0, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 0, 0},
			{0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0},
			{0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0},
			{0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0},
			{0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0},
		}, nil

	case "g":
		return 3, 6, [][]byte{
			{0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0},
			{0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0},
			{0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0},
			{0, 1, 1, 1, 1, 1, 2, 2, 2, 2, 1, 1, 1, 1, 1, 0},
			{0, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 0},
			{1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1},
			{1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1},
			{1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1},
			{1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1},
			{1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1},
			{1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1},
			{0, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 0},
			{0, 1, 1, 1, 1, 1, 2, 2, 2, 2, 1, 1, 1, 1, 1, 0},
			{0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0},
			{0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0},
			{0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0},
		}, nil

	case "C":
		return 6, 12, [][]byte{
			{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
			{0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0},
			{0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0},
			{0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0},
			{0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0},
			{0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0},
			{0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0},
			{0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0},
			{0, 1, 1, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1, 0},
			{0, 1, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1, 0},
			{0, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 0},
			{1, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1},
			{1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1},
			{1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1},
			{1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1},
			{1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1},
			{1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1},
			{1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1},
			{1, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1},
			{0, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 0},
			{0, 1, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1, 0},
			{0, 1, 1, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1, 0},
			{0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0},
			{0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0},
			{0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0},
			{0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0},
			{0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0},
			{0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0},
			{0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0},
			{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
		}, nil

	case "c":
		return 4, 8, [][]byte{
			{0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0},
			{0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0},
			{0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0},
			{0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0},
			{0, 0, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 0, 0},
			{0, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 0},
			{0, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 0},
			{1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1},
			{1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1},
			{1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1},
			{1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1},
			{1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1},
			{1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1},
			{1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1},
			{1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1},
			{0, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 0},
			{0, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 0},
			{0, 0, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 0, 0},
			{0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0},
			{0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0},
			{0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0},
			{0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0},
		}, nil
	}
	return 0, 0, nil, fmt.Errorf("ReachMatrix function doesn't understand size category \"%s\"", sizeCode)
}

//
// CustomFormatString replaces a %s in a user-supplied format with the given string.
// We do it this way to prevent the possibility of format string injection attacks
// or simple mistakes in forming a valid Printf-compatible format on the part of the
// user, at the expense of enabling fancy formatting.
//
// Only one %s is recognized for substitution. The others will simply be left as-is.
// DO NOT pass the returned string to Printf-like functions as the format argument;
// only consider this to be a data string.
//
func CustomFormatString(format, data string) string {
	parts := strings.SplitN(format, "%s", 2)
	if len(parts) == 1 {
		// there's no %s, so just return it as-is
		return format
	}
	return parts[0] + data + parts[1]
}

//
// SnapCoord converts a canvas coordinate to the nearest grid-snap destination.
//
func SnapCoord(x, objSnap, rScale float64) float64 {
	if objSnap == 0 {
		return x
	}
	return math.Floor((x+(rScale/objSnap)/2.0)/(rScale/objSnap)) * (rScale / objSnap)
}

//
// CanvasToGrid scales down canvas coordinates to grid units.
//
func CanvasToGrid(x float64, iScale int) float64 {
	return math.Floor(x / float64(iScale))
}

//
// GridToCanvas scales up grid units to canvas coordinates.
//
func GridToCanvas(x float64, iScale int) float64 {
	return x * float64(iScale)
}

//
// GridDistance calculates the distance between (x1,y1) and (x2,y2).
// The distance is rounded toward zero.
//
func GridDistance(x1, y1, x2, y2 float64) float64 {
	return math.Round(math.Sqrt(math.Pow(x1-x2, 2) + math.Pow(y1-y2, 2)))
}

//
// GridDeltaDistance calculates the straight-line distance from separate
// x and y distances, rounded toward zero.
//
func GridDeltaDistance(dx, dy float64) float64 {
	return math.Round(math.Sqrt(math.Pow(dx, 2) + math.Pow(dy, 2)))
}

//
// DistanceAlongRoute calculates the total linear path length along
// a path described by a slice of coordinate pairs, in order.
//
// XXX the tcl version called ScreenXYToGridXY on all of the coordinates
// but we don't here.
//
func DistanceAlongRoute(coordList []mapper.Coordinates) float64 {
	var distance float64
	var x, y float64

	for i, point := range coordList {
		if i > 0 {
			distance += GridDistance(x, y, point.X, point.Y)
		}
		x = point.X
		y = point.Y
	}
	return distance
}

//
// CacheMapID obfuscates a filename into an opaque string to thwart
// enumerating the server for all files. This is a simple conversion
// based on the module ID. If you wish to thwart enumeration even
// more, add an arbitrary <secret> string to perturb the hash of
// the name in a way that your players won't be able to predict
// easily.
//
func CacheMapID(path, module, secret string) string {
	if slash := strings.LastIndex(path, string(os.PathSeparator)); slash >= 0 {
		path = path[slash+1:]
	}
	if dot := strings.LastIndex(path, "."); dot > 0 {
		path = path[:dot]
	}
	sumData := md5.Sum([]byte(module + secret + path))
	return strings.ReplaceAll(
		strings.ReplaceAll(
			base64.StdEncoding.WithPadding(base64.NoPadding).EncodeToString(sumData[:]),
			"+", "_"),
		"/", "-")
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
