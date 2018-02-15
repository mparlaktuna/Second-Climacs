(cl:in-package #:climacs-syntax-common-lisp)

;;; This generic function is called on any wad.  It determines what
;;; kind of wad it is and either calls some specific indentation
;;; function, or some default one.
(defgeneric compute-child-indentations (wad client))

;;; By default, we do nothing.
(defmethod compute-child-indentations (wad client)
  (declare (ignore wad client))
  nil)

;;; This function is called when we have a simple form, and we have no
;;; particular information about the operator, i.e. either the
;;; operator is a LAMBDA expression, a symbol that is know to be the
;;; name of a function, but the lambda list of of that function is
;;; very simple, or a symbol that we have no information about.
(defun indent-default-function-call (wad client)
  (let ((children (children wad)))
    (unless (null (rest children))
      (let* ((first-child (first children))
             (first-child-start-line (start-line first-child))
             (first-child-start-column (start-column first-child)))
        (unless (zerop first-child-start-line)
          ;; If the start line of the first child is 0, that means
          ;; that the first child is positioned on the same line as
          ;; the operator, so we do not modify its indentation.  If it
          ;; is different from 0, then we set the indentation to be 2
          ;; columns with respect to the start column of the wad.
          (setf (indentation first-child) (+ 2 (start-column wad))))
        (loop for child in (rest children)
              unless (zerop (start-line child))
                ;; If the start line of the child is 0, that means
                ;; that this child is positioned on the same line as
                ;; the previous child, so we do not modify its
                ;; indentation.  If it is different from 0, then we
                ;; set the indentation so that it aligns with the
                ;; start column of the first child of the wad.
                do (setf (indentation child) first-child-start-column)
              do (compute-child-indentations child client))))))

;;; We define a form to be SIMPLE if and only if it is a proper list,
;;; and if the elements of the list correspond exactly to the
;;; expression parse results of the children of WAD in the same order.

(defun children-correspond-p (form wad-children)
  (if (null form)
      (or (null wad-children)
          (and (not (typep (car wad-children)
                           'expression-wad))
               (children-correspond-p form (cdr wad-children))))
      (and (not (null wad-children))
           (if (typep (car wad-children) 'expression-wad)
               (and (eq (car form)
                        (expression (car wad-children)))
                    (children-correspond-p (cdr form)
                                           (cdr wad-children)))
               (children-correspond-p form (cdr wad-children))))))

(defun proper-list-p (object)
  (not (null (ignore-errors (list-length object)))))

(defun simple-form-p (wad)
  (let ((expression (expression wad)))
    (and (consp expression)
         (proper-list-p expression)
         (children-correspond-p expression (children wad)))))

;;; To indent the sub-forms of a composite form, we can not use the
;;; symbol of the operator of that form, because that symbol may not
;;; yet exist, and in fact, it may have a package prefix that is not
;;; the name of any existing package yet either.
;;;
;;; But we would like to use a generic function to implement
;;; indentation, so that we can use an EQL specializer for the
;;; operator and a CLIENT instance for client-specific indentation
;;; styles.  And we can not use strings for EQL specializers.
;;;
;;; We solve this problem with an idea due to Jan Moringer, namely to
;;; "intern" a pair consisting of a package name and a symbol name
;;; (both string) in a hash table, thereby creating a PAWN object
;;; that can then be used as an EQL specializer.
;;;
;;; Currently, we don't take care of garbage that may accumulate in
;;; the form of methods that can never be invoked, but we intend to
;;; address this problem later.

;;; The class of the pawns that will be used as EQL specializers.  We
;;; include the name of the package and the name of the symbol for
;;; debugging purposes.
(defclass pawn ()
  ((%package-name :initarg :package-name :reader package-name)
   (%symbol-name :initarg :symbol-name :reader symbol-name)))

;;; A hash table mapping pairs to pawns.  Each pair is a CONS cell
;;; with the package name in the CAR slot and the symbol name in the
;;; CDR slot.
(defparameter *pawns* (make-hash-table :test #'equal))

;;; The generic function called in order to compute the relative
;;; indentation of the children of WAD.  Each method defines an EQL
;;; specializer on the PAWN parameter.  Client code should specialize
;;; on its own CLIENT class.
(defgeneric compute-sub-form-indentations (wad pawn client))

(defun intern-pawn (package-name-designator symbol-name-designator)
  (let* ((package-name (string package-name-designator))
         (symbol-name (string symbol-name-designator))
         (key (cons package-name symbol-name)))
    (multiple-value-bind (existing-pawn present-p) (gethash key *pawns*)
      (if (null present-p)
          (setf (gethash key *pawns*)
                (make-instance 'pawn
                  :package-name package-name
                  :symbol-name symbol-name))
          existing-pawn))))

(defun find-pawn (package-name-designator symbol-name-designator)
  (let* ((package-name (string package-name-designator))
         (symbol-name (string symbol-name-designator))
         (key (cons package-name symbol-name)))
    (gethash key *pawns*)))

(defmethod compute-child-indentations ((wad expression-wad) client)
  (if (simple-form-p wad)
      (let ((first-child (first (children wad))))
        (if (and (typep first-child 'expression-wad)
                 (typep (expression first-child) 'legal-symbol-token))
            (let* ((token (expression first-child))
                   (pawn (find-pawn (package-name token)
                                    (name token))))
              (if (null pawn)
                  (indent-default-function-call wad client)
                  (compute-sub-form-indentations wad pawn client)))
            (indent-default-function-call wad client)))
      (indent-default-function-call wad client)))

(defun indent-body (column body-wads client)
  (loop for wad in body-wads
        unless (zerop (start-line wad))
          do (setf (indentation wad) column)
        do (compute-child-indentations wad client)))
