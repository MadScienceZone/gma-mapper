all: gma-mapper.6.pdf

gma-mapper.6.pdf: gma-mapper.6
	gma fmtman < $< | tbl | groff -man | ps2pdf - $@
