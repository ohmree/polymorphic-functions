(in-package typed-dispatch)

(defun valid-parameter-name-p (name)
  (and (symbolp name)
       (not (eq t name))
       (not (eq nil name))))

;; &key args would be stored in the form of a plist - that is: the cdr of the type-list
;; following the &key word should be a plist
(defun typed-lambda-list-p (list)
  "Returns five values:
  the first value indicates whether the given LIST is a TYPED-LAMBDA-LIST,
  the second is a UNTYPED-LAMBDA-LIST corresponding to the given LIST,
  the third is a LIST of TYPEs corresponding to the given LIST,
  the fourth is a LIST of PARAMETERs corresponding to the third value,
  the fifth is the processed lambda-list suitable for defining the lambda inside DEFUN-TYPED"
  (declare (type list list))
  (let ((typed-lambda-list-p   t)
        (untyped-lambda-list nil)
        (type-list           nil)
        (typed-param-list    nil)
        (processed-lambda-list nil))
    (macrolet ((update-with-and (obj)
                 `(if typed-lambda-list-p
                      (setq typed-lambda-list-p
                            (and typed-lambda-list-p ,obj))))
               (next (list)
                 `(setq ,list (cdr ,list))))
      ;; first process required args
      (loop :while (and typed-lambda-list-p list)
            :for param := (first list)
            :until (member param lambda-list-keywords)
            :do (update-with-and (listp param))
                (update-with-and (valid-parameter-name-p (first param)))
                (update-with-and (type-specifier-p (second param)))
                (update-with-and (null (cddr param))) ; max-length 2
                (when typed-lambda-list-p
                  (push (first param) untyped-lambda-list)
                  (push (first param) typed-param-list)
                  (push (first param) processed-lambda-list)
                  (push (second param) type-list))
                (next list))
      ;; optionally the &optional args
      (loop :for keyword :in '(&optional &key) :do
        ;; TODO: Processing &allow-other-keys and &rest
        (when (eq keyword (first list))
          (push keyword untyped-lambda-list)
          (push keyword processed-lambda-list)
          (push keyword type-list) ; require the &optional keyword in RETRIEVE-TYPED-FUNCTION
          (next list)
          (loop :while (and typed-lambda-list-p list)
                :for param := (first list)
                :until (member param lambda-list-keywords)
                :do (update-with-and (listp param))
                    (update-with-and (listp (first param)))
                    (update-with-and (null (cdddr param))) ; max-length 3
                    (update-with-and (destructuring-bind ((name type)
                                                          &optional default-value
                                                            (given-p nil given-p-p))
                                         param
                                       (if given-p-p
                                           (push (list name default-value given-p)
                                                 processed-lambda-list)
                                           (push (list name default-value)
                                                 processed-lambda-list))
                                       (and (valid-parameter-name-p name)
                                            (type-specifier-p type)
                                            (if given-p-p
                                                (valid-parameter-name-p given-p)
                                                t))))
                    (when typed-lambda-list-p
                      (push (first (first param))  untyped-lambda-list)
                      (push (first (first param))  typed-param-list)
                      (when (eq '&key keyword)
                        (push (intern (symbol-name (first (first param)))
                                      :keyword)
                              type-list))
                      (push (second (first param)) type-list))
                    (next list))))
      (update-with-and (handler-case (progn
                                       (parse-ordinary-lambda-list list)
                                       t)
                         (program-error (c)
                           (declare (ignore c))
                           nil)))
      (when typed-lambda-list-p
        (setq untyped-lambda-list
              (append (nreverse untyped-lambda-list)
                      list))
        (setq processed-lambda-list
              (append (nreverse processed-lambda-list)
                      list))))
    (check-type untyped-lambda-list untyped-lambda-list)
    (values typed-lambda-list-p
            untyped-lambda-list
            (nreverse type-list)
            (nreverse typed-param-list)
            processed-lambda-list)))

(deftype typed-lambda-list ()
  "Examples:
  ((a integer) (b integer))
  ((a integer) &optional ((b integer) 0 b-supplied-p))"
  `(satisfies typed-lambda-list-p))

(defun untyped-lambda-list-p (list)
  "Returns three values:
  the first value indicates if the given LIST is an UNTYPED-LAMBDA-LIST,
  if the first value is T, that is, if the LIST is an UNTYPED-LAMBDA-LIST, the second value is the list of PARAMETERs that will be considered for typed dispatch
  the third value is the processed typed lambda-list; in particular, it adds an \"argp\" to the &optional and &key args, to help the DEFINE-TYPED-FUNCTION produce the correct function. In the absence of both &optional and &key args, this is the same as the given LIST whenever LIST is a valid UNTYPED-LAMBDA-LIST"
  (declare (type list list))
  (let ((untyped-lambda-list-p t)
        (typed-param-list    nil)
        (processed-untyped-lambda-list nil))
    (macrolet ((update-with-and (obj)
                 `(if untyped-lambda-list-p
                      (setq untyped-lambda-list-p
                            (and untyped-lambda-list-p ,obj))))
               (next (list)
                 `(setq ,list (cdr ,list))))
      ;; first process required args
      (loop :while (and untyped-lambda-list-p list)
            :for param := (first list)
            :until (member param lambda-list-keywords)
            :do (update-with-and (and (symbolp param)
                                      (not (eq t param))))
                (when untyped-lambda-list-p
                  (push param typed-param-list)
                  (push param processed-untyped-lambda-list))
                (next list))
      ;; optionally the &optional args
      (loop :for keyword :in '(&optional &key) :do
        (when (eq keyword (first list))
          (push keyword processed-untyped-lambda-list)
          (next list)
          (loop :while (and untyped-lambda-list-p list)
                :for param := (first list)
                :until (member param lambda-list-keywords)
                :for param-list-p := (listp param)
                :for param-symbol := (etypecase param
                                       (symbol param)
                                       (list (first param)))
                :do (update-with-and (valid-parameter-name-p param-symbol))
                    (when untyped-lambda-list-p
                      (let ((optional-param (list param-symbol
                                                  nil
                                                  (gensym (symbol-name param-symbol)))))
                        (push (if param-list-p
                                  param
                                  optional-param)
                              typed-param-list)
                        (push (if param-list-p
                                  param
                                  optional-param)
                              processed-untyped-lambda-list)))
                    (next list))))
      (update-with-and (handler-case (progn
                                       (parse-ordinary-lambda-list list)
                                       t)
                         (program-error (c)
                           (declare (ignore c))
                           nil)))
      (setq processed-untyped-lambda-list
            (append (nreverse processed-untyped-lambda-list) list)))
    (values untyped-lambda-list-p
            (nreverse typed-param-list)
            processed-untyped-lambda-list)))

(deftype untyped-lambda-list ()
  "Examples:
  (a b)
  (a b &optional c)
Non-examples:
  ((a string))"
  `(satisfies untyped-lambda-list-p))

