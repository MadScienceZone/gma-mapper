all: gma-mapper.5.pdf gma-style.conf.5.pdf

gma-mapper.5.pdf: gma-mapper.5
	gma fmtman < $< | groff -man | ps2pdf - $@

gma-style.conf.5.pdf: gma-style.conf.5
	gma fmtman < $< | groff -man | ps2pdf - $@
