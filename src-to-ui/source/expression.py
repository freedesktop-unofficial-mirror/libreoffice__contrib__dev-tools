#
# This file is part of the LibreOffice project.
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#

import sys
import globals

def toString (node):

    if node == None:
        return ''

    chars = '('

    if type(node.left) == type(0):
        chars += "%d"%node.left
    else:
        chars += toString(node.left)

    chars += node.op

    if type(node.right) == type(0):
        chars += "%d"%node.right
    else:
        chars += toString(node.right)

    chars += ")"

    return chars

class Node(object):
    def __init__ (self):
        self.left = None
        self.right = None
        self.parent = None
        self.op = None

class ExpParser(object):

    def __init__ (self, tokens):
        self.tokens = tokens

    def jumpToRoot (self):
        while self.ptr.parent != None:
            self.ptr = self.ptr.parent

    def build (self):
        self.ptr = Node()

        for token in self.tokens:

            if token in '+-':
                if self.ptr.left == None:
                    raise globals.AssertWrong
                if self.ptr.right == None:
                    self.ptr.op = token
                else:
                    self.jumpToRoot()
                    self.ptr.parent = Node()
                    self.ptr.parent.left = self.ptr
                    self.ptr = self.ptr.parent
                    self.ptr.op = token

            elif token in '*/':
                if self.ptr.left == None:
                    raise globals.AssertWrong
                elif self.ptr.right == None:
                    self.ptr.op = token
                else:
                    num = self.ptr.right
                    self.ptr.right = Node()
                    self.ptr.right.parent = self.ptr
                    self.ptr.right.left = num
                    self.ptr.right.op = token
                    self.ptr = self.ptr.right

            elif token == '(':
                if self.ptr.left == None:
                    self.ptr.left = Node()
                    self.ptr.left.parent = self.ptr
                    self.ptr = self.ptr.left
                elif self.ptr.right == None:
                    self.ptr.right = Node()
                    self.ptr.right.parent = self.ptr
                    self.ptr = self.ptr.right
                else:
                    raise globals.AssertWrong

            elif token == ')':
                if self.ptr.left == None:
                    raise globals.AssertWrong
                elif self.ptr.right == None:
                    raise globals.AssertWrong
                elif self.ptr.parent == None:
                    pass
                else:
                    self.ptr = self.ptr.parent

            else:
                num = int(token)
                if self.ptr.left == None:
                    self.ptr.left = num
                elif self.ptr.right == None:
                    self.ptr.right = num
                else:
                    raise globals.AssertWrong

    def dumpTree (self):
        self.jumpToRoot()
        print toString(self.ptr)




