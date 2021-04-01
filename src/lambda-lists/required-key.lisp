(in-package :adhoc-polymorphic-functions)

(defmethod %lambda-list-type ((type (eql 'required-key)) (lambda-list list))
  (let ((state :required))
    (dolist (elt lambda-list)
      (ecase state
        (:required (cond ((eq elt '&key)
                          (setf state '&key))
                         ((and *lambda-list-typed-p*   (listp elt)
                               (valid-parameter-name-p (first  elt))
                               (type-specifier-p       (second elt)))
                          t)
                         ((and (not *lambda-list-typed-p*)
                               (valid-parameter-name-p elt))
                          t)
                         (t
                          (return-from %lambda-list-type nil))))
        (&key (cond ((and *lambda-list-typed-p*
                          (listp elt)
                          (let ((elt (first elt)))
                            (and (listp elt)
                                 (valid-parameter-name-p (first  elt))
                                 (type-specifier-p       (second elt))))
                          (if (null (third elt))
                              t
                              (valid-parameter-name-p (third elt)))
                          (null (fourth elt)))
                     t)
                    ((and (not *lambda-list-typed-p*)
                          (valid-parameter-name-p elt))
                     t)
                    (t
                     (return-from %lambda-list-type nil))))))
    (eq state '&key)))

(def-test type-identification-key (:suite lambda-list)
  (is (eq 'required-key (lambda-list-type '(&key)))
      "(defun foo (&key)) does compile")
  (is (eq 'required-key (lambda-list-type '(a &key)))
      "(defun foo (a &key)) does compile")
  (is (eq 'required-key (lambda-list-type '(a &key b))))
  (is-error (lambda-list-type '(a &key 5)))
  (is-error (lambda-list-type '(a &key b &rest)))
  (is (eq 'required-key
          (lambda-list-type '((a string) (b number) &key
                              ((c number))) ; say if it actually is a null-type?
                            :typed t)))
  (is (eq 'required-key
          (lambda-list-type '((a string) (b number) &key
                              ((c number) 5 c))
                            :typed t)))
  (is (eq 'required-key
          (lambda-list-type '((a string) (b number) &key
                              ((c number) 5 c))
                            :typed t)))
  (is (eq 'required-key
          (lambda-list-type '((a string) (b number) &key
                              ((c number) b c))
                            :typed t)))
  (is-error (lambda-list-type '((a string) (b number) &key
                                ((c number) 5 6))
                              :typed t))
  (is-error (lambda-list-type '((a string) (b number) &key
                                ((c number) 5 6 7))
                              :typed t))
  (is-error (lambda-list-type '((a string) (b number) &key
                                (c number))
                              :typed t)))

(defmethod %defun-lambda-list ((type (eql 'required-key)) (lambda-list list))
  (let ((state       :required)
        (param-list ())
        (type-list  ()))
    (dolist (elt lambda-list)
      (ecase state
        (:required (cond ((eq elt '&key)
                          (push '&key param-list)
                          (push '&key type-list)
                          (setf state '&key))
                         ((not *lambda-list-typed-p*)
                          (push elt param-list))
                         (*lambda-list-typed-p*
                          (push (first  elt) param-list)
                          (push (second elt)  type-list))
                         (t
                          (return-from %defun-lambda-list nil))))
        (&key (cond ((not *lambda-list-typed-p*)
                     (push (list elt nil (gensym (symbol-name elt)))
                           param-list))
                    (*lambda-list-typed-p*
                     (push (cons (caar elt) (cdr elt))
                           param-list)
                     (push (list (intern (symbol-name (caar  elt))
                                         :keyword)
                                 (cadar elt))
                           type-list))
                    (t
                     (return-from %defun-lambda-list nil))))))
    (values (nreverse param-list)
            (let* ((type-list    (nreverse type-list))
                   (key-position (position '&key type-list)))
              (append (subseq type-list 0 key-position)
                      '(&key)
                      (sort (subseq type-list (1+ key-position)) #'string< :key #'first))))))

(def-test defun-lambda-list-key (:suite defun-lambda-list)
  (is (equalp '(a b &key)
              (defun-lambda-list '(a b &key))))
  (is-error (defun-lambda-list '(a b &rest args &key)))
  (destructuring-bind (first second third fourth)
      (defun-lambda-list '(a &key c d))
    (is (eq first 'a))
    (is (eq second '&key))
    (is (eq 'c (first third)))
    (is (eq 'd (first fourth))))
  (destructuring-bind ((first second third fourth) type-list)
      (multiple-value-list (defun-lambda-list '((a string) (b number) &key
                                                ((c number) 5))
                             :typed t))
    (is (eq first 'a))
    (is (eq second 'b))
    (is (eq third '&key))
    (is (equalp '(c 5) fourth))
    (is (equalp '(string number &key (:c number)) type-list))))

(defmethod %defun-body ((type (eql 'required-key)) (defun-lambda-list list))
  (assert (not *lambda-list-typed-p*))
  (let ((state       :required)
        (return-list ()))
    (loop :for elt := (first defun-lambda-list)
          :until (eq elt '&key)
          :do (unless (and (symbolp elt)
                           (not (member elt lambda-list-keywords)))
                (return-from %defun-body nil))
              (push elt return-list)
              (setf defun-lambda-list (rest defun-lambda-list)))
    (when (eq '&key (first defun-lambda-list))
      (setf state             '&key
            defun-lambda-list (rest defun-lambda-list))
      (labels ((key-p-tree (key-lambda-list)
                 (if (null key-lambda-list)
                     ()
                     (destructuring-bind (sym default symp) (first key-lambda-list)
                       (declare (ignore default))
                       (let ((recurse-result (key-p-tree (rest key-lambda-list))))
                         `(if ,symp
                              (cons ,(intern (symbol-name sym) :keyword)
                                    (cons ,sym ,recurse-result))
                              ,recurse-result))))))
        (let ((key-p-tree (key-p-tree defun-lambda-list)))
          (values (with-gensyms (apply-list)
                    `(let ((,apply-list ,key-p-tree))
                       (apply ,(polymorph-retriever-code type *name*
                                                         (append (reverse return-list)
                                                                 (list apply-list)))
                              ,@(reverse return-list)
                              ,apply-list)))
                  defun-lambda-list))))))

(defmethod %sbcl-transform-body-args ((type (eql 'required-key)) (typed-lambda-list list))
  (assert *lambda-list-typed-p*)
  (let ((key-position (position '&key typed-lambda-list)))
    (append (mapcar 'first (subseq typed-lambda-list 0 key-position))
            (loop :for ((param-name type) default) :in (subseq typed-lambda-list
                                                               (1+ key-position))
                  :appending `(,(intern (symbol-name param-name) :keyword)
                               ,param-name))
            '(nil))))

(defmethod %lambda-declarations ((type (eql 'required-key)) (typed-lambda-list list))
  (assert *lambda-list-typed-p*)
  (let ((state        :required)
        (declarations ()))
    (loop :for elt := (first typed-lambda-list)
          :until (eq elt '&key)
          :do (push `(type ,(second elt) ,(first elt)) declarations)
              (setf typed-lambda-list (rest typed-lambda-list)))
    (when (eq '&key (first typed-lambda-list))
      (setf state             '&key
            typed-lambda-list (rest typed-lambda-list))
      (loop :for elt := (first (first typed-lambda-list))
            :while elt
            :do (push `(type ,(second elt) ,(first elt)) declarations)
                (setf typed-lambda-list (rest typed-lambda-list))))
    `(declare ,@(nreverse declarations))))

(defmethod %type-list-compatible-p ((type (eql 'required-key))
                                    (type-list list)
                                    (untyped-lambda-list list))
  (let ((pos-key (position '&key type-list)))
    (unless (and (numberp pos-key)
                 (= pos-key (position '&key untyped-lambda-list)))
      (return-from %type-list-compatible-p nil))
    (let ((assoc-list (subseq type-list (1+ pos-key))))
      (loop :for param :in (subseq untyped-lambda-list (1+ pos-key))
            :do (unless (assoc-value assoc-list (intern (symbol-name param) :keyword))
                  (return-from %type-list-compatible-p nil))))
    t))

(defmethod applicable-p-function ((type (eql 'required-key)) (type-list list))
  (let* ((key-position (position '&key type-list))
         (param-list (loop :for i :from 0
                           :for type :in type-list
                           :collect (if (> i key-position)
                                        (type->param type '&key)
                                        (type->param type)))))
    `(lambda ,param-list
       (declare (optimize speed))
       (if *compiler-macro-expanding-p*
           (and ,@(loop :for param :in (subseq param-list 0 key-position)
                        :for type  :in (subseq type-list  0 key-position)
                        :collect `(our-typep ,param ',type))
                ,@(loop :for (param default supplied-p)
                          :in (subseq param-list (1+ key-position))
                        :for type  :in (subseq type-list (1+ key-position))
                        :collect `(or (not ,supplied-p)
                                      (our-typep ,param ',(second type)))))
           (and ,@(loop :for param :in (subseq param-list 0 key-position)
                        :for type  :in (subseq type-list  0 key-position)
                        :collect `(typep ,param ',type))
                ,@(loop :for (param default supplied-p)
                          :in (subseq param-list (1+ key-position))
                        :for type  :in (subseq type-list (1+ key-position))
                        :collect `(or (not ,supplied-p)
                                      (typep ,param ',(second type)))))))))

(defmethod %type-list-subtype-p ((type-1 (eql 'required-key))
                                 (type-2 (eql 'required-key))
                                 list-1 list-2)
  (declare (optimize speed)
           (type list list-1 list-2))
  (let ((key-position-1 (position '&key list-1))
        (key-position-2 (position '&key list-2)))
    (if (= key-position-1 key-position-2)
        (and (every #'subtypep
                    (subseq list-1 0 key-position-1)
                    (subseq list-2 0 key-position-2))
             (loop :for (param type) :in (subseq list-1 (1+ key-position-1))
                   :always (subtypep type (second (assoc (the symbol param)
                                                         (subseq list-2 (1+ key-position-2)))))))
        nil)))

(def-test type-list-subtype-key (:suite type-list-subtype-p)
  (5am:is-true  (type-list-subtype-p '(string &key (:a string))
                                     '(string &key (:a array))))
  (5am:is-true  (type-list-subtype-p '(string &key (:a string))
                                     '(array  &key (:a string))))
  (5am:is-true  (type-list-subtype-p '(string &key (:a string))
                                     '(string &key (:a string) (:b number))))
  (5am:is-false (type-list-subtype-p '(string &key (:a string))
                                     '(string &key (:a number))))
  (5am:is-false (type-list-subtype-p '(string &key (:a string))
                                     '(number &key (:a string))))
  (5am:is-false (type-list-subtype-p '(&key (:a string) (:b number))
                                     '(string &key (:a string) (:b number)))))

(defmethod %type-list-causes-ambiguous-call-p
    ((type-1 (eql 'required-key))
     (type-2 (eql 'required-key))
     list-1 list-2)
  (declare (optimize debug)
           (type list list-1 list-2))
  (let ((key-position-1 (position '&key list-1))
        (key-position-2 (position '&key list-2)))
    (and (= key-position-1 key-position-2)
         (every #'type=
               (subseq list-1 0 key-position-1)
               (subseq list-2 0 key-position-2)))))

(def-test type-list-causes-ambiguous-call-key
    (:suite type-list-causes-ambiguous-call-p)
  (5am:is-true  (type-list-causes-ambiguous-call-p '(string &key (:a string))
                                                   '(string &key (:a array))))
  (5am:is-true  (type-list-causes-ambiguous-call-p '(string &key (:a string))
                                                   '(string &key (:a number))))
  (5am:is-true  (type-list-causes-ambiguous-call-p '(string &key (:a string))
                                                   '(string &key (:a string) (:b number))))
  (5am:is-false (type-list-causes-ambiguous-call-p '(string &key (:a string))
                                                   '(number &key (:a string))))
  (5am:is-false (type-list-causes-ambiguous-call-p '(&key (:a string) (:b number))
                                                   '(string &key (:a string) (:b number)))))
