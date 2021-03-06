#!/usr/bin/env python
#
# This file is part of the LibreOffice project.
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#

import sys
import expression

def run (exp):
    tokens = exp.split()
    expparser = expression.ExpParser(tokens)
    expparser.build()
    expparser.dumpTree()

def main ():
    run("6 + 34")
    run("6 + 34 - 10")
    run("6 + 34 - 10 + 200")
    run("6 + 34 - 10 * 200")
    run("6 + 34 - 10 * 200 + 18")
    run("6 + 34 - 10 * 200 + 18 / 2")

    run("6 * ( ( 10 + 2 ) - 10 ) * 33")

if __name__ == '__main__':
    main()
