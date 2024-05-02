all: mapper.6.pdf

mapper.6.pdf: mapper.6
	gma fmtman < $< | tbl | groff -man | ps2pdf - $@
