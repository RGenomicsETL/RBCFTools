plugins/pgs.so: plugins/pgs.c
	$(CC) $(PLUGIN_FLAGS) $(CFLAGS) $(ALL_CPPFLAGS) $(EXTRA_CPPFLAGS) $(CHOLMOD_CPPFLAGS) $(LDFLAGS) -o $@ version.c $< $(PLUGIN_LIBS) $(LIBS) $(CHOLMOD_LIBS)
