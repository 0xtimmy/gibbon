#lang gibbon

(let ([x : Bool (eq? (quote hi) (quote there))])
  (let ([y : Bool (= 3 4)])
    (if x
        (if y 1 2)
        (if y 3 4))))
