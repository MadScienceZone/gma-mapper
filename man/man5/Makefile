all: mapper.5.pdf style.conf.5.pdf

mapper.5.pdf: mapper.5
	groff -man $< | ps2pdf - $@

style.conf.5.pdf: style.conf.5
	groff -man $< | ps2pdf - $@
