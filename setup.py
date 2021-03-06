import os
import os.path
import glob
import sys
import time
import subprocess
import shutil
import glob

if sys.version_info < (2, 7):
    print("yt currently requires Python version 2.7")
    print("certain features may fail unexpectedly and silently with older versions.")
    sys.exit(1)

import setuptools
from distutils.command.build_py import build_py
from numpy.distutils.misc_util import appendpath
from numpy.distutils.command import install_data as np_install_data
from numpy.distutils import log
from distutils import version

from distutils.core import Command
from distutils.spawn import find_executable

REASON_FILES = []
REASON_DIRS = [
    "",
    "resources",
    "resources/ux",
    "resources/images",
    "resources/css",
    "resources/css/images",
    "app",
    "app/store",
    "app/store/widgets",
    "app/view",
    "app/view/widgets",
    "app/model",
    "app/controller",
    "app/controller/widgets",
    "app/templates",
]

for subdir in REASON_DIRS:
    dir_name = os.path.join("yt", "gui", "reason", "html", subdir)
    files = []
    for ext in ["js", "html", "css", "png", "ico", "gif"]:
        files += glob.glob("%s/*.%s" % (dir_name, ext))
    REASON_FILES.append((dir_name, files))

# Verify that we have Cython installed
REQ_CYTHON = '0.22'
try:
    import Cython
    needs_cython = \
        version.LooseVersion(Cython.__version__) < version.LooseVersion(REQ_CYTHON)
except ImportError as e:
    needs_cython = True

if needs_cython:
    print("Cython is a build-time requirement for the source tree of yt.")
    print("Please either install yt from a provided, release tarball,")
    print("or install Cython (version %s or higher)." % REQ_CYTHON)
    print("You may be able to accomplish this by typing:")
    print("     pip install -U Cython")
    sys.exit(1)

######
# This next bit comes from Matthew Brett, to get Cython working with NumPy
# distutils.  I added a bit to get C++ Cython working.
from os.path import join as pjoin, dirname
from distutils.dep_util import newer_group
from distutils.errors import DistutilsError


def generate_a_pyrex_source(self, base, ext_name, source, extension):
    ''' Monkey patch for numpy build_src.build_src method

    Uses Cython instead of Pyrex.

    Assumes Cython is present
    '''
    if self.inplace:
        target_dir = dirname(base)
    else:
        target_dir = appendpath(self.build_src, dirname(base))
    if extension.language == "c++":
        cplus = True
        file_ext = ".cpp"
    else:
        cplus = False
        file_ext = ".c"
    target_file = pjoin(target_dir, ext_name + file_ext)
    depends = [source] + extension.depends
    if self.force or newer_group(depends, target_file, 'newer'):
        import Cython.Compiler.Main
        log.info("cythonc:> %s" % (target_file))
        self.mkpath(target_dir)
        options = Cython.Compiler.Main.CompilationOptions(
            defaults=Cython.Compiler.Main.default_options,
            include_path=extension.include_dirs,
            cplus=cplus,
            output_file=target_file)
        cython_result = Cython.Compiler.Main.compile(source,
                                                     options=options)
        if cython_result.num_errors != 0:
            raise DistutilsError("%d errors while compiling %r with Cython"
                                 % (cython_result.num_errors, source))
    return target_file


from numpy.distutils.command import build_src
build_src.build_src.generate_a_pyrex_source = generate_a_pyrex_source
# End snippet
######

VERSION = "3.2"

if os.path.exists('MANIFEST'):
    os.remove('MANIFEST')


def get_mercurial_changeset_id(target_dir):
    """adapted from a script by Jason F. Harris, published at

    http://jasonfharris.com/blog/2010/05/versioning-your-application-with-the-mercurial-changeset-hash/

    """
    import subprocess
    import re
    get_changeset = subprocess.Popen('hg identify -b -i',
                                     stdout=subprocess.PIPE,
                                     stderr=subprocess.PIPE,
                                     shell=True)

    if (get_changeset.stderr.read() != ""):
        print("Error in obtaining current changeset of the Mercurial repository")
        changeset = None

    changeset = get_changeset.stdout.read().strip().decode("UTF-8")
    if (not re.search("^[0-9a-f]{12}", changeset)):
        print("Current changeset of the Mercurial repository is malformed")
        changeset = None

    return changeset


class my_build_src(build_src.build_src):
    def run(self):
        build_src.build_src.run(self)


class my_build_py(build_py):
    def run(self):
        # honor the --dry-run flag
        if not self.dry_run:
            target_dir = os.path.join(self.build_lib, 'yt')
            src_dir = os.getcwd()
            changeset = get_mercurial_changeset_id(src_dir)
            self.mkpath(target_dir)
            with open(os.path.join(target_dir, '__hg_version__.py'), 'w') as fobj:
                fobj.write("hg_version = '%s'\n" % changeset)

        build_py.run(self)


def configuration(parent_package='', top_path=None):
    from numpy.distutils.misc_util import Configuration

    config = Configuration(None, parent_package, top_path)
    config.set_options(ignore_setup_xxx_py=True,
                       assume_default_configuration=True,
                       delegate_options_to_subpackages=True,
                       quiet=True)

    config.make_config_py()
    # config.make_svn_version_py()
    config.add_subpackage('yt', 'yt')
    config.add_scripts("scripts/*")

    return config


def setup_package():

    from numpy.distutils.core import setup

    setup(
        name="yt",
        version=VERSION,
        description="An analysis and visualization toolkit for Astrophysical "
                    + "simulations.",
        classifiers=["Development Status :: 5 - Production/Stable",
                     "Environment :: Console",
                     "Intended Audience :: Science/Research",
                     "License :: OSI Approved :: BSD License",
                     "Operating System :: MacOS :: MacOS X",
                     "Operating System :: POSIX :: AIX",
                     "Operating System :: POSIX :: Linux",
                     "Programming Language :: C",
                     "Programming Language :: Python",
                     "Topic :: Scientific/Engineering :: Astronomy",
                     "Topic :: Scientific/Engineering :: Physics",
                     "Topic :: Scientific/Engineering :: Visualization"],
        keywords='astronomy astrophysics visualization ' +
        'amr adaptivemeshrefinement',
        entry_points={'console_scripts': [
        'yt = yt.utilities.command_line:run_main',
        ],
            'nose.plugins.0.10': [
                'answer-testing = yt.utilities.answer_testing.framework:AnswerTesting'
            ]
        },
        author="Matthew J. Turk",
        author_email="matthewturk@gmail.com",
        url="http://yt-project.org/",
        license="BSD",
        configuration=configuration,
        zip_safe=False,
        data_files=REASON_FILES,
        cmdclass={'build_py': my_build_py, 'build_src': my_build_src},
    )
    return

if __name__ == '__main__':
    setup_package()
