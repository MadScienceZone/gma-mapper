all: mapper.6.pdf

mapper.6.pdf: mapper.6
	tbl $< | groff -man | ps2pdf - $@
