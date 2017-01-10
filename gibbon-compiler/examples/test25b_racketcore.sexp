#lang gibbon

(require "../../ASTBenchmarks/grammar_racket.sexp")

;; This can be run on any file from disk:
(define (foo [e : Toplvl]) : Int
  (case e
    ;; In the same order as the data def:
    [(DefineValues   listSymA exprA) 101]
    [(DefineSyntaxes listSymB exprB) 102]
    [(BeginTop listToplvl)         103]
    [(Expression x)                104]
    ))
    ;[Expression Expr]

(foo (Expression (VARREF (quote hi))))
