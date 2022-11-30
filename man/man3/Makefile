all: gmautil.3.pdf ustar.3.pdf

gmautil.3.pdf: gmautil.3
	groff -man $< | ps2pdf - $@

ustar.3.pdf: ustar.3
	groff -man $< | ps2pdf - $@
