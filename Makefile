# h/t to @jimhester and @yihui for this parse block:
# https://github.com/yihui/knitr/blob/dc5ead7bcfc0ebd2789fe99c527c7d91afb3de4a/Makefile#L1-L4
# Note the portability change as suggested in the manual:
# https://cran.r-project.org/doc/manuals/r-release/R-exts.html#Writing-portable-packages
PKGNAME := $(shell sed -n "s/Package: *\([^ ]*\)/\1/p" DESCRIPTION)
PKGVERS := $(shell sed -n "s/Version: *\([^ ]*\)/\1/p" DESCRIPTION)

# Platform-specific library path variable
UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
	LIBPATH_VAR = DYLD_LIBRARY_PATH
else
	LIBPATH_VAR = LD_LIBRARY_PATH
endif

all: check



rd:
	$(LIBPATH_VAR)=$(CURDIR)/inst/htslib/lib:$(CURDIR)/inst/bcftools/lib:$$$(LIBPATH_VAR) R -e 'roxygen2::roxygenize()'
build: install_deps
	R CMD build .

check: build
	R CMD check --as-cran --no-manual $(PKGNAME)_$(PKGVERS).tar.gz

install_deps:
	R \
	-e 'if (!requireNamespace("remotes")) install.packages("remotes")' \
	-e 'remotes::install_deps(dependencies = TRUE)'

install: build
	R CMD INSTALL $(PKGNAME)_$(PKGVERS).tar.gz
install2:
	R CMD INSTALL --no-configure .
install3:
	R CMD INSTALL  .
clean:
	@rm -rf $(PKGNAME)_$(PKGVERS).tar.gz $(PKGNAME).Rcheck
format:
	air format .
# Development targets
dev-install:
	R CMD INSTALL --preclean .

test: dev-install
	R -e 'tinytest::test_package("$(PKGNAME)")'

test-dev: install2
	R -e 'library("$(PKGNAME)") ; tinytest::run_test_dir("inst/tinytest")'

test-vcf: install2
	bash test.sh inst/extdata/test_deep_variant.vcf.gz
	
test-vcf-bcf: install2
	bash test.sh /mnt/NGS/ProNAS/ulcwgs/analyses/methyl_RND/variantcalls/Toure_Mahamane_Sounkou_S33/test_2.bcf

rdm: dev-install
	R -e "rmarkdown::render('README.Rmd')"

rdm2:
	R -e "rmarkdown::render('README.Rmd')"

# Docker build targets
docker-build-release:
	docker build -f Dockerfile -t rbcftools:$(PKGVERS)-release .

docker-build-dev:
	docker build --build-arg BUILD_MODE=develop -f Dockerfile -t rbcftools:$(PKGVERS)-dev .

docker-build-all: docker-build-release docker-build-dev
	@echo "Built both release and dev containers"

docker-clean:
	docker rmi rbcftools:$(PKGVERS)-release rbcftools:$(PKGVERS)-dev 2>/dev/null || true

.PHONY: all rd build check install_deps install clean dev-install dev-test dev-preprocess-test dev-parse-test dev-all-tests docker-build-release docker-build-dev docker-build-all docker-clean
