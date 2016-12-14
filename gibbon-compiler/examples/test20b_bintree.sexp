#lang s-exp "../gibbon.rkt"

(data Tree
      [Leaf Int]
      [Node Tree Tree])

(define (build-tree [n : Int]) : Tree
  (if (= n 0)
      (Leaf 1)
      (let ([l : Tree (build-tree (- n 1))]
            [r : Tree (build-tree (- n 1))])
        (Node l r))))

;; Non-recursive, two-level match:
;; This is actually a hard one -- it requires copy insertion.
(define (sum-tree [tr : Tree]) : Int
  (case tr
    [(Leaf n) n]
    [(Node x y)
     (+ (case x
          [(Leaf m) m]
          [(Node a b) 100])
        (case y
          [(Leaf q) q]
          [(Node r s) 100]))]))

;; Here we time a fold over the tree:
(let ((tr0 : Tree (build-tree (size-param))))
  (iterate (sum-tree tr0)))
