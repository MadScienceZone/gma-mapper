all: mapper.6.pdf

mapper.6.pdf: mapper.6
	groff -man $< | ps2pdf - $@
