all: mapper-protocol.7.pdf

mapper-protocol.7.pdf: mapper-protocol.7
	tbl $< | groff -man | ps2pdf - $@
