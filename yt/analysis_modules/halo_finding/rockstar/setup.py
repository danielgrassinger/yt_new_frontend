#!/usr/bin/env python
from __future__ import print_function
import setuptools
import os, sys, os.path

import os.path

def configuration(parent_package='',top_path=None):
    from numpy.distutils.misc_util import Configuration
    config = Configuration('rockstar',parent_package,top_path)
    config.make_config_py() # installs __config__.py
    #config.make_svn_version_py()
    try:
        rd = open("rockstar.cfg").read().strip()
    except IOError:
        print("Reading Rockstar location from rockstar.cfg failed.")
        print("Please place the base directory of your")
        print("Rockstar install in rockstar.cfg and restart.")
        print("(ex: \"echo '/path/to/Rockstar-0.99' > rockstar.cfg\" )")
        sys.exit(1)
    config.add_extension("rockstar_interface",
                         "yt/analysis_modules/halo_finding/rockstar/rockstar_interface.pyx",
                         library_dirs=[rd],
                         libraries=["rockstar"],
                         #define_macros = [("THREADSAFE", "__thread")],
                         define_macros = [("THREADSAFE", "")],
                         include_dirs=[rd,
                                       os.path.join(rd, "io"),
                                       os.path.join(rd, "util")])
    config.add_extension("rockstar_groupies",
                         "yt/analysis_modules/halo_finding/rockstar/rockstar_groupies.pyx",
                         library_dirs=[rd],
                         libraries=["rockstar"],
                         #define_macros = [("THREADSAFE", "__thread")],
                         define_macros = [("THREADSAFE", "")],
                         include_dirs=[rd,
                                       os.path.join(rd, "io"),
                                       os.path.join(rd, "util")])
    return config

