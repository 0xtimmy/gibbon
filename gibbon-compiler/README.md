
A prototype compiler for the Gibbon language, a simple functional
language for writing tree traversals.

The main feature of the Gibbon compiler is that it transforms programs
to automatically operate over serialized versions of algebraic data
types, rather than over their natural, pointer-based representations.


Further reading
---------------

Aside from looking at the code documentation, you may want to read
about the basic intermediate languages that the compiler uses.

 * [L1](src/Packed/FirstOrder/L1)
 * [L2](src/Packed/FirstOrder/L2)
 * [L3](src/Packed/FirstOrder/L3)
 * [L4](src/Packed/FirstOrder/L4)

You can also read the ECOOP'17 paper, however it is already
substantially out of date (as of 2017.08.01).

For developers: Coding Style
----------------------------

For this project, please follow the coding style described here:

https://github.com/rrnewton/haskell-style-guide/blob/master/RRN_style_guide.md

