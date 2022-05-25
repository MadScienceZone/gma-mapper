module github.com/MadScienceZone/gma-mapper/v4

go 1.18

replace (
	github.com/MadScienceZone/atk => ../atk
	github.com/MadScienceZone/atk/tk => ../atk/tk
	github.com/MadScienceZone/atk/tk/interp => ../atk/tk/interp
	github.com/MadScienceZone/go-gma/v4 => ../go-gma
	github.com/MadScienceZone/go-gma/v4/util => ../go-gma/util
)

require (
	github.com/MadScienceZone/atk v1.2.2
	github.com/MadScienceZone/go-gma/v4 v4.3.12
	github.com/google/uuid v1.3.0
	github.com/lestrrat-go/strftime v1.0.6
)

require (
	github.com/pkg/errors v0.9.1 // indirect
	github.com/schwarmco/go-cartesian-product v0.0.0-20180515110546-d5ee747a6dc9 // indirect
	golang.org/x/exp v0.0.0-20220518171630-0b5c67f07fdf // indirect
	golang.org/x/sync v0.0.0-20210220032951-036812b2e83c // indirect
)
