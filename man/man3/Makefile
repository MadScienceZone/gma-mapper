all: gmafile.3.pdf gmaproto.3.pdf gmautil.3.pdf ustar.3.pdf gmacolors.3.pdf

gmacolors.3.pdf: gmacolors.3
	groff -man $< | ps2pdf - $@

gmafile.3.pdf: gmafile.3
	groff -man $< | ps2pdf - $@

gmaproto.3.pdf: gmaproto.3
	groff -man $< | ps2pdf - $@

gmautil.3.pdf: gmautil.3
	tbl $< | groff -man | ps2pdf - $@

ustar.3.pdf: ustar.3
	groff -man $< | ps2pdf - $@
