all: mapper-protocol.7.pdf

mapper-protocol.7.pdf: mapper-protocol.7
	gma fmtman < $< | tbl | groff -man | ps2pdf - $@
