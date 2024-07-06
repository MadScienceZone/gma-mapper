all: gma-mapper-protocol.7.pdf

gma-mapper-protocol.7.pdf: gma-mapper-protocol.7
	gma fmtman < $< | tbl | groff -man | ps2pdf - $@
