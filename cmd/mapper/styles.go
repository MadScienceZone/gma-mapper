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
	"fmt"
	"os"

	"github.com/MadScienceZone/go-gma/v4/mapper"
)

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
