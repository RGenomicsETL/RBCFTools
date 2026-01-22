# The pgs plugin requires CHOLMOD library for sparse matrix operations
# Only build if HAVE_CHOLMOD is yes
ifeq ($(HAVE_CHOLMOD),yes)
plugins/pgs.so: plugins/pgs.c
	@echo "Building pgs plugin with CHOLMOD support"
	@touch $@
	$(CC) $(PLUGIN_FLAGS) $(CFLAGS) $(ALL_CPPFLAGS) $(EXTRA_CPPFLAGS) $(CHOLMOD_CPPFLAGS) $(LDFLAGS) -o $@ version.c $< $(PLUGIN_LIBS) $(LIBS) $(CHOLMOD_LIBS)
else
plugins/pgs.so:
	@echo "notice plugin requires CHOLMOD library, skipping build"
	@touch $@
endif