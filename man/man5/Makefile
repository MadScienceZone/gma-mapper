all: mapper.5.pdf style.conf.5.pdf

mapper.5.pdf: mapper.5
	gma fmtman < $< | groff -man | ps2pdf - $@

style.conf.5.pdf: style.conf.5
	gma fmtman < $< | groff -man | ps2pdf - $@
