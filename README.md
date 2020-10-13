# typed-functions

Provides {macro, structures and hash-table}-based wrappers around normal functions to allow for dispatching on types instead of classes. See [examples](#examples).

>This library is still experimental. The interface itself hasn't changed much since the start. 
>
>I might rename the library later. `overloaded-functions` is one possible name. Please suggest a better name! It is recommended that users either `:use` it, or alias it with package-local-nicknames to avoid renaming troubles later.

## Why?

- ANSI standard provided generic functions work do not work on parametric types `(array double-float)`. 
- As of 2020, there exists [fast-generic-functions](https://github.com/marcoheisig/fast-generic-functions) that allows generic-functions to be, well, fast. 
- With MOP, it might be possible to enable `cl:defmethod` on parametric types. No one I know of has tried this yet. I'm unfamiliar with MOP, and felt it might just be quicker to put this together. There also exists [specialization-store](https://github.com/markcox80/specialization-store) that provides support for parametric-types (or just the more-than-class types).
- `specialization-store` has its own MOP and runs into about 3.5k LOC without tests. Besides the seeming code complexity, there are some aspects of `specialization-store` I didn't find very convenient. See [the section below](#comparison-with-specialization-store).
- `fast-generic-functions` runs into about 900 LOC without tests.
- `typed-functions` takes about 1.5k LOC with tests and, to me, it seems that is also fulfils the goal of `fast-generic-functions`.

## Comparison with specialization-store

A more broader concern is the premise of specialization-store: no matter what specialization is invoked, the final-result should be the same. What may differ is the *process* in which the result is computed.

This [manifests itself](https://github.com/markcox80/specialization-store/issues/8) in differing approaches about how the `&optional` and `&key` dispatching plays out. For instance, consider 

```lisp
(defstore foo (a &key b))
(defspecialization foo ((a string) &key (b string)) t
  'hello)
```

This does not allow for a default-value for `b` in the specialization, without redefining the `(defstore foo ...)` form to include a newer `init-form` for `b`.

```lisp
(define-typed-function foo (a &key b))
(defun-typed foo ((a string) &key ((b string) "hello")) t
  'hello)
```

If you do not require extensibility on anything other than `required` arguments, you should be happy with `specialization-store`. It also provides great-enough run-time performance comparable to the standard `cl:generic-function`s. (See the next section.)

Further, at the moment, `typed-functions` provides no support for dispatching on `&rest` arguments. Raise an issue if this support is needed!

`typed-functions` should provide quite a few compiler-notes to aid the user in debugging and optimizing; it should be possible to provide this for `specialization-store` using a wrapper macro. See [this discussion](https://github.com/markcox80/specialization-store/issues/6#issuecomment-692958498) for a start.

## Comparison of generics, specializations and typed-functions

For the run-time performance, consider the below definitions

```lisp
(defpackage :perf-test
  (:use :cl :specialization-store :typed-functions))
(in-package :perf-test)

(defmethod generic-= ((a string) (b string))
  (string= a b))

(defstore specialized-= (a b))
(defspecialization (specialized-= :inline t) ((a string) (b string)) t
  (string= a b))

(defstore specialized-=-key (&key a b))
(defspecialization (specialized-=-key :inline t) (&key (a string) (b string)) t
(string= a b))

(define-typed-function typed-= (a b))
(defun-typed typed-= ((a string) (b string)) t
  (string= a b))

(define-typed-function typed-=-key (&key a b))
(defun-typed typed-=-key (&key ((a string) "") ((b string) "")) t
  (string= a b))
```

For a 1,000,000 calls to each in the format

```lisp
(let ((a "hello")
      (b "world"))
  (time (loop repeat 1000000 do (string= a b))))
```

the performance results come out as:

```
0.001 sec   | naive string=
0.110 sec   | generic-=
0.120 sec   | specialized-=
0.323 sec   | specialized-=-key
0.748 sec   | typed-=
1.170 sec   | typed-=-key
```

However, both `specialization-store` and `typed-functions` (as well as `fast-generic-functions`) provide support for compile-time optimizations via type-declarations and/or inlining. If performance is a concern, one'd therefore rather want to use compile-time optimizations.

| Feature                         | cl:generic-function | specialization-store | typed-functions |
|:--------------------------------|:--------------------|:---------------------|:---------------|
| Method combination              | Yes                 | No                   | No             |
| Precedence                      | Yes                 | Partial*             | No             |
| &optional, &key, &rest dispatch | No                  | Yes                  | Yes^           |
| Run-time Speed                  | Fast                | Fast                 | Slow           |
| Compile-time support            | Partial**           | Yes                  | Yes            |

\*`specialization-store` allows dispatching on the most specialized specialization; `typed-functions` provides no such support.

^See [#comparison-with-specialization-store](#comparison-with-specialization-store).
Well...

\*\*Using [fast-generic-functions](https://github.com/marcoheisig/fast-generic-functions) - but this apparantly has a few limitations like requiring non-builtin-classes to have an additional metaclass. This effectively renders it impossible to use for the classes in already existing libraries. 

## An Ideal Way Forward

- The designer should know MOP to extend `cl:generic-function` to provide dispatching based on typed
- The resulting work should not have the above limitation of `fast-generic-functions`
- Should provide compile-time optimizations, as well as compiler-notes to help user optimize / debug their code

## Examples
- 
See [src/misc-tests.lisp](src/misc-tests.lisp) for some more examples.

```lisp
(use-package :typed-functions)
(define-typed-function my= (a b))
(defun-typed my= ((a string) (b string)) boolean
  (string= a b))
(defun-typed my= ((a character) (b character)) boolean
  (char= a b))
(defun-typed my= ((a (simple-array single-float))
                  (b (simple-array single-float))) symbol
  ;; possible here; not possible with cl:defmethod without some MOP-fu
  ;; do something
  'hello)
```

```lisp
CL-USER> (defun foo (a b)
           (declare (optimize speed)
                    (type string a b))
           (string= a b))

FOO
CL-USER> (disassemble 'foo)
; disassembly for FOO
; Size: 39 bytes. Origin: #x5300D1B3                          ; FOO
; B3:       31F6             XOR ESI, ESI
; B5:       48C745F017011050 MOV QWORD PTR [RBP-16], #x50100117  ; NIL
; BD:       488975E8         MOV [RBP-24], RSI
; C1:       48C745E017011050 MOV QWORD PTR [RBP-32], #x50100117  ; NIL
; C9:       B90C000000       MOV ECX, 12
; CE:       FF7508           PUSH QWORD PTR [RBP+8]
; D1:       B8E25A3550       MOV EAX, #x50355AE2              ; #<FDEFN SB-KERNEL:STRING=*>
; D6:       FFE0             JMP RAX
; D8:       CC10             INT3 16                          ; Invalid argument count trap
NIL
CL-USER> (defun bar (a b)
           (declare (optimize speed)
                    (type string a b))
           (my= a b))
BAR
CL-USER> (disassemble 'bar)
; disassembly for BAR
; Size: 39 bytes. Origin: #x5300D283                          ; BAR
; 83:       31F6             XOR ESI, ESI
; 85:       48C745F017011050 MOV QWORD PTR [RBP-16], #x50100117  ; NIL
; 8D:       488975E8         MOV [RBP-24], RSI
; 91:       48C745E017011050 MOV QWORD PTR [RBP-32], #x50100117  ; NIL
; 99:       B90C000000       MOV ECX, 12
; 9E:       FF7508           PUSH QWORD PTR [RBP+8]
; A1:       B8E25A3550       MOV EAX, #x50355AE2              ; #<FDEFN SB-KERNEL:STRING=*>
; A6:       FFE0             JMP RAX
; A8:       CC10             INT3 16                          ; Invalid argument count trap
NIL
CL-USER> (my= (make-array 1 :element-type 'single-float)
              (make-array 1 :element-type 'single-float))
HELLO
CL-USER> (defun baz (a b)
           (declare (type string a)
                    (type integer b))
           (my= a b))
; While compiling (MY= A B): 
;   No applicable TYPED-FUNCTION discovered for TYPE-LIST (STRING INTEGER).
;   Available TYPE-LISTs include:
;      ((SIMPLE-ARRAY SINGLE-FLOAT) (SIMPLE-ARRAY SINGLE-FLOAT))
;      (CHARACTER CHARACTER)
;      (STRING STRING)
BAZ
CL-USER> (my= 5 "hello")
; Evaluation aborted on #<TYPED-FUNCTIONS::NO-APPLICABLE-TYPED-FUNCTION {103A713D13}>.
```

## Dependencies outside quicklisp

- SBCL 2.0.9+
- [trivial-types:function-name](https://github.com/digikar99/trivial-types)
- [compiler-macro](https://github.com/Bike/compiler-macro)

## Other Usage Notes

- `define-typed-function` (should) have no effect if the name is already registered as a `typed-function(-wrapper)`. Use `undefine-typed-function` to deregister the name.
- At `(debug 3)`, typed-functions (should) checks for the existence of multiple applicable `typed-function`s; otherwise, the first applicable `typed-function` is chosen.

### Limitations

At least one limitation stems from the limitations of the implementations (and CL?) themselves:

```lisp
CL-USER> (defun bar ()
           (declare (optimize speed))
           (my= "hello" (macrolet ((a () "hello"))
                          (a))))
; Unable to optimize (MY= "hello"
                        (MACROLET ((A ()
                                     "hello"))
                          (A))) because ... (the reason may change from time to time)
BAR
CL-USER> (defun bar ()
           (declare (optimize speed))
           (my= "hello" (the string
                             (macrolet ((a () "hello"))
                               (a)))))
BAR
CL-USER> (disassemble 'bar)
; disassembly for BAR
; Size: 13 bytes. Origin: #x5300799B                          ; BAR
; 9B:       BA4F011050       MOV EDX, #x5010014F              ; T
; A0:       488BE5           MOV RSP, RBP
; A3:       F8               CLC
; A4:       5D               POP RBP
; A5:       C3               RET
; A6:       CC10             INT3 16                          ; Invalid argument count trap
NIL
```

And while this is a simpler case that could possibly be optimizable, a nuanced discussion pertaining to the same is at [https://github.com/Bike/compiler-macro/pull/6#issuecomment-643613503](https://github.com/Bike/compiler-macro/pull/6#issuecomment-643613503).

