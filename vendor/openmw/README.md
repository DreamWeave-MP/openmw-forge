# Original OpenMW tarball builder: retained inputs

This directory holds the original OpenMW tarball builder's packaging templates, including the **upstream POSIX runtime launcher** and package contents notice. Its Bash build orchestration was replaced by `src/native_openmw.jsl` and `src/plan.jsl`.

The templates are embedded into the stand-alone compiled Jess application via `src/assets.jsl`. The POSIX launcher is distributed inside OpenMW tarballs; it is **not** used to orchestrate building or packaging OpenMW.

Refer to the root `README.md` and `docs/AUDIT.md` for usage and original-script mapping.
