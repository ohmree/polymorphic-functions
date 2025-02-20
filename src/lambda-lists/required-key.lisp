(in-package :polymorphic-functions)

(defmethod %lambda-list-type ((type (eql 'required-key)) (lambda-list list))
  (let ((state :required))
    (dolist (elt lambda-list)
      (ecase state
        (:required (cond ((eq elt '&key)
                          (setf state '&key))
                         ((and *lambda-list-typed-p*   (listp elt)
                               (valid-parameter-name-p (first  elt)))
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
                                 (valid-parameter-name-p (first  elt))))
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

(defmethod %effective-lambda-list ((type (eql 'required-key)) (lambda-list list))
  (let ((state               :required)
        (param-list          ())
        (type-list           ())
        (effective-type-list ()))
    (dolist (elt lambda-list)
      (ecase state
        (:required (cond ((and (eq elt '&key)
                               *lambda-list-typed-p*)
                          (push '&key param-list)
                          (push '&key type-list)
                          (push '&key effective-type-list)
                          (setf state '&key))
                         ((and (eq elt '&key)
                               (not *lambda-list-typed-p*))
                          (push '&rest param-list)
                          (push (gensym "ARGS") param-list)
                          (push '&key param-list)
                          (setf state '&key))
                         ((not *lambda-list-typed-p*)
                          (push elt param-list))
                         (*lambda-list-typed-p*
                          (push (first  elt) param-list)
                          (push (second elt) type-list)
                          (push (second elt) effective-type-list))
                         (t
                          (return-from %effective-lambda-list nil))))
        (&key (cond ((not *lambda-list-typed-p*)
                     (push (list elt nil (gensym (symbol-name elt)))
                           param-list))
                    (*lambda-list-typed-p*
                     ;; FIXME: Handle the case when keyword is non-default
                     (destructuring-bind ((name type) &optional (default nil defaultp)
                                                        name-supplied-p-arg) elt
                       (push (if name-supplied-p-arg
                                 (list name default name-supplied-p-arg)
                                 (list name default))
                             param-list)
                       (push (list (intern (symbol-name name) :keyword)
                                   type)
                             type-list)
                       (push (list (intern (symbol-name name) :keyword)
                                   (cond ((and defaultp (subtypep 'null type))
                                          type)
                                         (defaultp `(or null ,type))
                                         ((not defaultp) type)))
                             effective-type-list)))
                    (t
                     (return-from %effective-lambda-list nil))))))
    (if *lambda-list-typed-p*
        (values (nreverse param-list)
                (let* ((type-list    (nreverse type-list))
                       (key-position (position '&key type-list)))
                  (append (subseq type-list 0 key-position)
                          '(&key)
                          (sort (subseq type-list (1+ key-position)) #'string< :key #'first)))
                (let* ((effective-type-list    (nreverse effective-type-list))
                       (key-position (position '&key effective-type-list)))
                  (append (subseq effective-type-list 0 key-position)
                          '(&key)
                          (sort (subseq effective-type-list
                                        (1+ key-position)) #'string< :key #'first))))
        (nreverse param-list))))

(def-test effective-lambda-list-key (:suite effective-lambda-list)
  (is-error (compute-effective-lambda-list '(a b &rest args &key)))
  (destructuring-bind (first second third fourth fifth sixth)
      (compute-effective-lambda-list '(a &key c d))
    (declare (ignore third))
    (is (eq first 'a))
    (is (eq second '&rest))
    (is (eq fourth '&key))
    (is (eq 'c (first fifth)))
    (is (eq 'd (first sixth))))
  (destructuring-bind ((first second third fourth) type-list effective-type-list)
      (multiple-value-list (compute-effective-lambda-list '((a string) (b number) &key
                                                            ((c number) 5))
                                                          :typed t))
    (is (eq first 'a))
    (is (eq second 'b))
    (is (eq third '&key))
    (is (equalp '(c 5) fourth))
    (is (equalp type-list
                '(string number &key (:c number))))
    (is (equalp effective-type-list
                '(string number &key (:c (or null number)))))))

(defmethod compute-polymorphic-function-lambda-body
    ((type (eql 'required-key)) (untyped-lambda-list list) &optional invalidated-p)
  (let* ((rest-position       (position '&rest untyped-lambda-list))
         (required-parameters (subseq untyped-lambda-list 0 rest-position))
         (keyword-parameters  (subseq untyped-lambda-list (+ 3 rest-position)))
         (rest-args           (nth (1+ rest-position) untyped-lambda-list))
         (block-name          (blockify-name *name*)))
    `((declare (ignorable ,@(mapcar #'first keyword-parameters)
                          ,@(mapcar #'third keyword-parameters))
               (dynamic-extent ,rest-args)
               (optimize speed))
      (block ,block-name
        ,(if invalidated-p
             `(progn
                (update-polymorphic-function-lambda (fdefinition ',*name*))
                (apply (fdefinition ',*name*) ,@required-parameters ,rest-args))
             `(apply
               (the function
                    (locally (declare #+sbcl (sb-ext:muffle-conditions sb-ext:compiler-note))
                      (cond
                        ,@(loop
                            :for i :from 0
                            :for polymorph :in (polymorphic-function-polymorphs
                                                (fdefinition *name*))
                            :for static-dispatch-name
                              := (polymorph-static-dispatch-name polymorph)
                            :for runtime-applicable-p-form
                              := (polymorph-runtime-applicable-p-form polymorph)
                            :collect
                            `(,runtime-applicable-p-form #',static-dispatch-name))
                        (t
                         (return-from ,*name*
                           (funcall ,(polymorphic-function-default (fdefinition *name*))
                                    ',*name* (list* ,@required-parameters ,rest-args)))))))
               ,@required-parameters ,rest-args))))))

(defmethod %sbcl-transform-arg-lvars-from-lambda-list-form ((type (eql 'required-key))
                                                            (untyped-lambda-list list))
  (assert (not *lambda-list-typed-p*))
  (let ((key-position (position '&key untyped-lambda-list)))
    `(append ,@(loop :for arg :in (subseq untyped-lambda-list 0 key-position)
                     :collect `(list (cons ',arg ,arg)))
             ,@(loop :for param-name :in (subseq untyped-lambda-list
                                                 (1+ key-position))
                     :collect `(if ,param-name
                                   ,(let ((keyword (intern (symbol-name param-name) :keyword)))
                                      `(list (cons ,keyword ,keyword)
                                             (cons ',param-name ,param-name)))
                                   nil)))))

(defmethod %lambda-declarations ((type (eql 'required-key)) (typed-lambda-list list))
  (assert *lambda-list-typed-p*)
  (let ((declarations ()))
    (loop :for elt := (first typed-lambda-list)
          :until (eq elt '&key)
          :do (push (if (type-specifier-p (second elt))
                        `(type ,(second elt) ,(first elt))
                        `(type ,(upgrade-extended-type (second elt)) ,(first elt)))
                    declarations)
              (setf typed-lambda-list (rest typed-lambda-list)))
    (when (eq '&key (first typed-lambda-list))
      (setf typed-lambda-list (rest typed-lambda-list))
      (loop :for elt := (first (first typed-lambda-list))
            :while elt
            :do (push (if (type-specifier-p (second elt))
                          `(type ,(second elt) ,(first elt))
                          `(type ,(upgrade-extended-type (second elt)) ,(first elt)))
                      declarations)
                (setf typed-lambda-list (rest typed-lambda-list))))
    `(declare ,@(nreverse declarations))))

(defmethod enhanced-lambda-declarations ((type (eql 'required-key))
                                         (type-list list)
                                         (param-list list)
                                         (arg-types list)
                                         &optional return-type)
  (destructuring-bind (name parameterizer) (or (cdr return-type) '(nil nil))
    (let ((declarations ()))
      (loop :for arg := (first param-list)
            :for arg-type := (first arg-types)
            :until (eq arg '&key)
            :do (push `(type ,arg-type ,arg) declarations)
                (when (eq name arg) (setq return-type (funcall parameterizer arg-type)))
                (setf param-list (rest param-list))
                (setf arg-types  (rest arg-types)))
      (when (eq '&key (first param-list))
        (setf param-list (rest param-list)
              type-list  (rest (member '&key type-list)))
        (loop :for key := (let ((arg-type (first arg-types)))
                            (when arg-type
                              (assert (and (listp arg-type)
                                           (eq 'eql (first arg-type))
                                           (null (cddr arg-type))))
                              (second arg-type)))
              :while key
              :for arg := (let ((arg (find key param-list
                                           :test (lambda (key arg)
                                                   (string= key
                                                            (etypecase arg
                                                              (symbol arg)
                                                              (list (first arg))))))))
                            (etypecase arg
                              (symbol arg)
                              (list (first arg))))
              :for arg-type := (second arg-types)
              :do (push `(type ,arg-type ,arg) declarations)
                  (when (eq name arg) (setq return-type (funcall parameterizer arg-type)))
                  (setf arg-types  (cddr arg-types))
                  (setf param-list (remove key param-list
                                           :test (lambda (first second)
                                                   (string= first
                                                            (etypecase second
                                                              (symbol second)
                                                              (list (first second))))))))
        (loop :while param-list
              :for arg := (let ((arg (first param-list)))
                            (etypecase arg
                              (symbol arg)
                              (list (first arg))))
              :for original-type := (second (assoc arg type-list :test #'string=))
              :do (push `(type ,original-type ,arg) declarations)
                  (when (eq name arg) (setq return-type (funcall parameterizer original-type)))
                  (setf arg-types  (cddr arg-types))
                  (setf param-list (remove arg param-list
                                           :test (lambda (first second)
                                                   (string= first
                                                            (etypecase second
                                                              (symbol second)
                                                              (list (first second)))))))))
      (values `(declare ,@(nreverse declarations))
              return-type))))

(defmethod %type-list-compatible-p ((type (eql 'required-key))
                                    (type-list list)
                                    (untyped-lambda-list list))
  (let ((pos-key  (position '&key type-list))
        (pos-rest (position '&rest untyped-lambda-list)))
    (unless (and (numberp pos-key)
                 (numberp pos-rest)
                 (= pos-key pos-rest))
      (return-from %type-list-compatible-p nil))
    (let ((assoc-list (subseq type-list (1+ pos-key))))
      (loop :for (param default paramp) :in (subseq untyped-lambda-list (+ pos-key 3))
            :do (unless (assoc-value assoc-list (intern (symbol-name param) :keyword))
                  (return-from %type-list-compatible-p nil))))
    t))

(defmethod compiler-applicable-p-lambda-body ((type (eql 'required-key))
                                              (untyped-lambda-list list)
                                              (type-list list))
  (let* ((key-position (position '&key type-list))
         (param-list (loop :for i :from 0
                           :for type :in type-list
                           :collect (if (> i key-position)
                                        (type->param type '&key)
                                        (type->param type))))
         (ll-param-alist (loop :for i :from 0
                               :for param :in (set-difference param-list lambda-list-keywords)
                               :for name :in (set-difference untyped-lambda-list
                                                             lambda-list-keywords)
                               :collect (cons name param))))
    (with-gensyms (form form-type)
      `(lambda ,param-list
         (declare (optimize speed))
         (and ,@(loop :for param :in (subseq param-list 0 key-position)
                      :for type  :in (subseq type-list  0 key-position)
                      :collect
                      `(let ((,form      (car ,param))
                             (,form-type (cdr ,param)))
                         (cond ((eq t ',type)
                                t)
                               ((eq t ,form-type)
                                (signal 'form-type-failure
                                        :form ,form))
                               (t
                                (subtypep ,form-type
                                          ,(deparameterize-compile-time-type type
                                                                             ll-param-alist))))))
              ,@(loop :for (param default supplied-p)
                        :in (subseq param-list (1+ key-position))
                      :for type  :in (subseq type-list (1+ key-position))
                      :collect
                      `(let ((,form      (car ,param))
                             (,form-type (cdr ,param)))
                         (cond ((eq t ',type)
                                t)
                               ((eq t ,form-type)
                                (signal 'form-type-failure
                                        :form ,form))
                               (t
                                (subtypep ,form-type
                                          ,(deparameterize-compile-time-type (second type)
                                                                             ll-param-alist)))))))))))

(defmethod runtime-applicable-p-form ((type (eql 'required-key))
                                      (untyped-lambda-list list)
                                      (type-list list)
                                      (parameter-alist list))
  (let* ((rest-position (position '&rest untyped-lambda-list))
         (key-position  (position '&key untyped-lambda-list))
         (param-list    untyped-lambda-list))
    `(and ,@(loop :for param :in (subseq param-list 0 rest-position)
                  :for type  :in (subseq type-list  0 rest-position)
                  :collect `(typep ,param ,(deparameterize-runtime-type type parameter-alist)))
          ,@(let ((param-types (subseq type-list (1+ rest-position))))
              (loop :for (param default supplied-p)
                      :in (subseq param-list (1+ key-position))
                    :for type := (second (assoc param param-types :test #'string=))
                    :collect `(typep ,param ,(deparameterize-runtime-type type
                                                                          parameter-alist)))))))

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
                (subseq list-2 0 key-position-2))
         (let ((list-1 (subseq list-1 (1+ key-position-1)))
               (list-2 (subseq list-2 (1+ key-position-2))))
           (multiple-value-bind (shorter-alist longer-alist)
               (if (<= (length list-1) (length list-2))
                   (values list-1 list-2)
                   (values list-2 list-1))
             (and (loop :for (key type) :in shorter-alist
                        :always (if-let (type-2 (second (assoc key longer-alist)))
                                  (or (type= type type-2)
                                      (and (typep nil type)
                                           (typep nil type-2)))
                                  (return-from %type-list-causes-ambiguous-call-p nil)))
                  (loop :for (key type) :in (set-difference longer-alist shorter-alist
                                                            :key #'first)
                        :always (typep nil type))))))))

(def-test type-list-causes-ambiguous-call-key
    (:suite type-list-causes-ambiguous-call-p)
  (5am:is-true  (type-list-causes-ambiguous-call-p '(string &key (:a (or null string)))
                                                   '(string &key (:a (or null array)))))
  (5am:is-true  (type-list-causes-ambiguous-call-p '(string &key (:a string))
                                                   `(string &key (:a string)
                                                            (:b (or null number)))))
  (5am:is-false (type-list-causes-ambiguous-call-p '(string &key (:a string))
                                                   '(string &key (:a string) (:b number))))
  (5am:is-false (type-list-causes-ambiguous-call-p '(string &key (:a string))
                                                   '(string &key (:a number))))
  (5am:is-false (type-list-causes-ambiguous-call-p '(string &key (:a string))
                                                   '(string &key (:a array))))
  (5am:is-false (type-list-causes-ambiguous-call-p '(string &key (:a string))
                                                   '(number &key (:a string))))
  (5am:is-false (type-list-causes-ambiguous-call-p '(&key (:a string) (:b number))
                                                   '(string &key (:a string) (:b number)))))
