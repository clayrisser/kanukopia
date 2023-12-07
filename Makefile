DESTDIR ?=
PREFIX ?= /usr/local
BINDIR ?= $(PREFIX)/bin

ifeq (,$(DESTDIR))
SUDO ?= sudo
endif

.PHONY: sudo
sudo:
	@$(SUDO) true

.PHONY: install
install: kanukopia.sh sudo
	@$(SUDO) cp $< $(DESTDIR)$(BINDIR)/kanukopia
	@$(SUDO) chmod +x $(DESTDIR)$(BINDIR)/kanukopia

.PHONY: uninstall
uninstall: kanukopia.sh sudo
	@$(SUDO) rm -f $(DESTDIR)$(BINDIR)/kanukopia
