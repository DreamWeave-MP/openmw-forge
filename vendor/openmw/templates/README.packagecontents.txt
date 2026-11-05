=== Package Content README ===

This package contains Linux binaries for openmw and its suite of utilities. It is intended to run on most moderately old and recent Linux distributions. These archives are built on Alma Linux and should work on any distribution with glibc 2.34 or later when the configured symbol-version audit passes.

=== Running the provided binaries ===
The binaries depend on libraries that might not be installed on your system or in an incompatible version. Therefore these libraries are included in the "lib" subdirectory. To automatically use the provided libraries there are scripts which set the LD_LIBRARY_PATH variable to the "lib" directory.

To run openmw or a utility simply run the provided shell script (the file without a suffix -> <filename> not <filename>.x86_64). In case of openmw this would be "openmw" not openmw.x86_64.
