#!/bin/bash -e

# This file is part of the LibreOffice project.
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#

# Run this script to download, build and install the validators.

if [ -z "$1" -o -z "$2" ]; then
    echo "Usage: $0 <workdir> <instdir>"
    echo
    echo "Example: $0 $HOME/scm/svn /opt/lo/bin"
    exit 1
fi

if ! type -p mvn >/dev/null; then
    echo "Error: can't find mvn in PATH"

    if [ -e /etc/os-release ]; then
        . /etc/os-release
        if [ "$NAME" == "openSUSE" ]; then
            echo "Hint: type 'zypper -p http://download.opensuse.org/repositories/devel:/tools:/building/openSUSE_$VERSION_ID/ in maven' to install it."
        fi
    fi
    exit 1
fi

if ! type -p ant >/dev/null; then
    echo "Error: can't find ant in PATH"

    if [ -e /etc/os-release ]; then
        . /etc/os-release
        if [ "$NAME" == "openSUSE" ]; then
            echo "Hint: type 'zypper in ant-junit' to install it."
        fi
    fi
    exit 1
fi

instdir="$2"
if [ ! -d "$instdir" ]; then
    echo "Error: please create '$instdir'."
    exit 1
fi

workdir="$1"
if [ ! -d "$workdir" ]; then
    mkdir -p "$workdir"
fi

# ODF validation

cd "$workdir"
if [ ! -d odf ]; then
    svn co https://svn.apache.org/repos/asf/incubator/odf/trunk odf
fi
cd odf
if [ ! -e validator/target/odfvalidator-*-incubating-SNAPSHOT-jar-with-dependencies.jar ]; then
    mvn install -DskipTests
fi

cd "$instdir"
cat > odfvalidator << EOF
#!/usr/bin/env bash
java -Djavax.xml.validation.SchemaFactory:http://relaxng.org/ns/structure/1.0=org.iso_relax.verifier.jaxp.validation.RELAXNGSchemaFactoryImpl -Dorg.iso_relax.verifier.VerifierFactoryLoader=com.sun.msv.verifier.jarv.FactoryLoaderImpl -jar $workdir/odf/validator/target/odfvalidator-*-incubating-SNAPSHOT-jar-with-dependencies.jar -e "\$@"
EOF
chmod +x odfvalidator

# OOXML validation

cd "$workdir"
if [ ! -d officeotron ]; then
    svn co http://officeotron.googlecode.com/svn/trunk officeotron
fi
cd officeotron
if [ ! -e dist/officeotron-*.jar ]; then
    ant
fi

cd "$instdir"
cat > officeotron << EOF
#!/usr/bin/env bash
java -jar $workdir/officeotron/dist/officeotron-*.jar "\$@"
EOF
chmod +x officeotron

# vi:set shiftwidth=4 expandtab:
