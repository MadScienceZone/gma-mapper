all: gmafile.3.pdf gmaproto.3.pdf gmautil.3.pdf gma-ustar.3.pdf gmacolors.3.pdf gma-mapper.3.pdf

gma-mapper.3.pdf: gma-mapper.3
	gma fmtman < $< | groff -man | ps2pdf - $@

gmacolors.3.pdf: gmacolors.3
	gma fmtman < $< | groff -man | ps2pdf - $@

gmafile.3.pdf: gmafile.3
	gma fmtman < $< | groff -man | ps2pdf - $@

gmaproto.3.pdf: gmaproto.3
	gma fmtman < $< | groff -man | ps2pdf - $@

gmautil.3.pdf: gmautil.3
	gma fmtman < $< | tbl | groff -man | ps2pdf - $@

gma-ustar.3.pdf: gma-ustar.3
	gma fmtman < $< | groff -man | ps2pdf - $@
