#lang s-exp "../gibbon/gibbon.rkt"

;; use structs/data instead of sexp
(provide typecheck-expr
         Int_ Bool_ Lamt NullT P S N B Begin Lam App Null
	 CONSEXPR NULLEXPR CONSPARAM NULLPARAM CONSTYPE NULLTYPE)

(data ListExpr
      [CONSEXPR Expr ListExpr]
      [NULLEXPR])

(data ListParam
      [CONSPARAM Param ListParam]
      [NULLPARAM])

(data ListType
      [CONSTYPE Type ListType]
      [NULLTYPE])      

(data Type
      [Int_]
      [Bool_]
      [NullT]
      [Lamt ListType Type])

(data Param
      [P Expr Type])

(data Expr
      [Null]
      [S Sym]
      [N Int]
      [B Bool] ;; leaving out null for now
      [Begin ListExpr]
      [Lam ListParam Expr]
      [App Expr ListExpr])

(define (extend-env [e : (SymDict Type)] [sym : Sym] [type : Type]) : (SymDict Type)
  (insert e sym type))

(define (lookup-env [e : (SymDict Type)] [sym : Sym]) : Type
  (lookup e sym))

(define (typecheck-begin [exprs : ListExpr] [env : (SymDict Type)]) : Type
  (case exprs
    [(CONSEXPR e rest)
     (case rest
      [(CONSEXPR e2 rest2)
       (let ([t : Type (typecheck e env)])
         (typecheck-begin rest env))]
      [(NULLEXPR)
       (typecheck e env)])]
    [(NULLEXPR)
     (error "Should never get here: ~a\n" exprs)]))

(define (lam-extend-env [params : ListParam] [env : (SymDict Type)]) : (SymDict Type)
  (case params
    [(CONSPARAM param rest)
     (let ([nenv : (SymDict Type) (case param
       	  	            	    [(P e t)
        		  	     (case e
	 		 	       [(S sym)
      		          	        (extend-env env sym t)])])])
       (lam-extend-env rest nenv))]
    [(NULLPARAM)
     env]))
     
(define (type-equal-list? [l1 : ListType] [l2 : ListType]) : Bool
  (case l1
    [(CONSTYPE t1 rest1)
     (case l2
       [(CONSTYPE t2 rest2)
        (if (type-equal? t1 t2)
	    (type-equal-list? rest1 rest2)
	    #f)]
       [(NULLTYPE) #f])]
    [(NULLTYPE)
     (case l2
       [(CONSTYPE t2 rest2) #f]
       [(NULLTYPE)          #t])]))
    
(define (type-equal? [t1 : Type] [t2 : Type]) : Bool
  (case t1
    [(NullT)
     (case t2
       [(NullT) #t]
       [(Int_) #f]
       [(Bool_) #f]
       [(Lamt pt bt) #f])]
    [(Int_)
     (case t2
       [(Int_) #t]
       [(Bool_) #f]
       [(NullT) #f]
       [(Lamt pt bt) #f])]
    [(Bool_)
     (case t2
       [(Bool_) #t]
       [(Int_) #f]
       [(NullT) #f]
       [(Lamt pt bt) #f])]
    [(Lamt pt bt)
     (case t2
       [(Lamt pt2 bt2)
        (and
         (type-equal-list? pt pt2)
         (type-equal? bt bt2))]
       [(Int_) #f]
       [(Bool_) #f]
       [(NullT) #f])]))
        
(define (params-args-equal? [ptypes : ListType] [args : ListExpr] [env : (SymDict Type)]) : Bool
  (case ptypes
    [(NULLTYPE)
     (case args
      [(CONSEXPR e rest) (error "Args and Params not same length.")]
      [(NULLEXPR) #t])]
    [(CONSTYPE t rest)
     (case args
       [(CONSEXPR e rest2)
        (if (type-equal? t (typecheck e env))
	    (params-args-equal? rest rest2 env)
	    #f)]
       [(NULLEXPR) (error "Args and Params not same length.")])]))

(define (getParamTypes [params : ListParam]) : ListType
  (case params
    [(CONSPARAM param rest)
     (case param
       [(P e t) (CONSTYPE t (getParamTypes rest))])]
    [(NULLPARAM)
     (NULLTYPE)]))

(define (typecheck [expr : Expr] [env : (SymDict Type)] ): Type
  (case expr
    [(Null)
     (NullT)]
    [(S sym)
     (lookup-env env sym)]
    [(N n)
     (Int_)]
    [(B b)
     (Bool_)]
    [(Begin ls)
     (typecheck-begin ls env)]
    [(Lam params body)
     (Lamt (getParamTypes params)
     	   (typecheck body (lam-extend-env params env)))]
    [(App lam args)
     (case (typecheck lam env)
       [(Lamt ptypes btype)
        (if (params-args-equal? ptypes args env)
            btype
            (error "no type"))])]))

(define (typecheck-expr [expr : Expr]) : Type
  (typecheck expr (empty-dict)))

