;;; find-func.el --- find the definition of the Emacs Lisp function near point

;; Copyright (C) 1997, 1999, 2001, 2004  Free Software Foundation, Inc.

;; Author: Jens Petersen <petersen@kurims.kyoto-u.ac.jp>
;; Maintainer: petersen@kurims.kyoto-u.ac.jp
;; Keywords: emacs-lisp, functions, variables
;; Created: 97/07/25

;; This file is part of GNU Emacs.

;; GNU Emacs is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.

;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 59 Temple Place - Suite 330,
;; Boston, MA 02111-1307, USA.

;;; Commentary:
;;
;; The funniest thing about this is that I can't imagine why a package
;; so obviously useful as this hasn't been written before!!
;; ;;; find-func
;; (find-function-setup-keys)
;;
;; or just:
;;
;; (load "find-func")
;;
;; if you don't like the given keybindings and away you go!  It does
;; pretty much what you would expect, putting the cursor at the
;; definition of the function or variable at point.
;;
;; The code started out from `describe-function', `describe-key'
;; ("help.el") and `fff-find-loaded-emacs-lisp-function' (Noah Friedman's
;; "fff.el").

;;; Code:

(require 'loadhist)

;;; User variables:

(defgroup find-function nil
  "Finds the definition of the Emacs Lisp symbol near point."
;;   :prefix "find-function"
  :group 'lisp)

(defconst find-function-space-re "\\(?:\\s-\\|\n\\|;.*\n\\)+")

(defcustom find-function-regexp
  ;; Match things like (defun foo ...), (defmacro foo ...),
  ;; (define-skeleton foo ...), (define-generic-mode 'foo ...),
  ;;  (define-derived-mode foo ...), (define-minor-mode foo)
  (concat
   "^\\s-*(\\(def\\(ine-skeleton\\|ine-generic-mode\\|ine-derived-mode\\|\
\[^cgv\W]\\w+\\*?\\)\\|define-minor-mode\
\\|easy-mmode-define-global-mode\\)" find-function-space-re
   "\\('\\|\(quote \\)?%s\\(\\s-\\|$\\|\(\\|\)\\)")
  "The regexp used by `find-function' to search for a function definition.
Note it must contain a `%s' at the place where `format'
should insert the function name.  The default value avoids `defconst',
`defgroup', `defvar'.

Please send improvements and fixes to the maintainer."
  :type 'regexp
  :group 'find-function
  :version "21.1")

(defcustom find-variable-regexp
  (concat"^\\s-*(def[^umag]\\(\\w\\|\\s_\\)+\\*?" find-function-space-re "%s\\(\\s-\\|$\\)")
  "The regexp used by `find-variable' to search for a variable definition.
It should match right up to the variable name.  The default value
avoids `defun', `defmacro', `defalias', `defadvice', `defgroup'.

Please send improvements and fixes to the maintainer."
  :type 'regexp
  :group 'find-function
  :version "21.1")

(defcustom find-function-source-path nil
  "The default list of directories where `find-function' searches.

If this variable is nil then `find-function' searches `load-path' by
default."
  :type '(repeat directory)
  :group 'find-function)

(defcustom find-function-recenter-line 1
  "The window line-number from which to start displaying a symbol definition.
A value of nil implies center the beginning of the definition.
See `find-function' and `find-variable'."
  :type '(choice (const :tag "Center" nil)
		 integer)
  :group 'find-function
  :version "20.3")

(defcustom find-function-after-hook nil
  "Hook run after finding symbol definition.

See the functions `find-function' and `find-variable'."
  :group 'find-function
  :version "20.3")

;;; Functions:

(defun find-library-suffixes ()
  (let ((suffixes nil))
    (dolist (suffix load-suffixes (nreverse suffixes))
      (unless (string-match "elc" suffix) (push suffix suffixes)))))

(defun find-library-name (library)
  "Return the full name of the elisp source of LIBRARY."
  ;; If the library is byte-compiled, try to find a source library by
  ;; the same name.
  (if (string-match "\\.el\\(c\\(\\..*\\)?\\)\\'" library)
      (setq library (replace-match "" t t library)))
  (or (locate-file library
		   (or find-function-source-path load-path)
		   (append (find-library-suffixes) '("")))
      (error "Can't find library %s" library)))

(defvar find-function-C-source-directory
  (let ((dir (expand-file-name "src" source-directory)))
    (when (and (file-directory-p dir) (file-readable-p dir))
      dir))
  "Directory where the C source files of Emacs can be found.
If nil, do not try to find the source code of functions and variables
defined in C.")

(defun find-function-C-source (fun-or-var file variable-p)
  "Find the source location where SUBR-OR-VAR is defined in FILE.
VARIABLE-P should be non-nil for a variable or nil for a subroutine."
  (unless find-function-C-source-directory
    (setq find-function-C-source-directory
	  (read-directory-name "Emacs C source dir: " nil nil t)))
  (setq file (expand-file-name file find-function-C-source-directory))
  (unless (file-readable-p file)
    (error "The C source file %s is not available"
	   (file-name-nondirectory file)))
  (unless variable-p
    (setq fun-or-var (indirect-function fun-or-var)))
  (with-current-buffer (find-file-noselect file)
    (goto-char (point-min))
    (unless (re-search-forward
	     (if variable-p
		 (concat "DEFVAR[A-Z_]*[ \t\n]*([ \t\n]*\""
			 (regexp-quote (symbol-name fun-or-var))
			 "\"")
	       (concat "DEFUN[ \t\n]*([ \t\n]*\""
		       (regexp-quote (subr-name fun-or-var))
		       "\""))
	     nil t)
      (error "Can't find source for %s" fun-or-var))
    (cons (current-buffer) (match-beginning 0))))

;;;###autoload
(defun find-library (library)
  "Find the elisp source of LIBRARY."
  (interactive
   (list
    (completing-read "Library name: "
		     'locate-file-completion
		     (cons (or find-function-source-path load-path)
			   (find-library-suffixes)))))
  (let ((buf (find-file-noselect (find-library-name library))))
    (condition-case nil (switch-to-buffer buf) (error (pop-to-buffer buf)))))

;;;###autoload
(defun find-function-search-for-symbol (symbol variable-p library)
  "Search for SYMBOL.
If VARIABLE-P is nil, `find-function-regexp' is used, otherwise
`find-variable-regexp' is used.  The search is done in library LIBRARY."
  (if (null library)
      (error "Don't know where `%s' is defined" symbol))
  ;; Some functions are defined as part of the construct
  ;; that defines something else.
  (while (and (symbolp symbol) (get symbol 'definition-name))
    (setq symbol (get symbol 'definition-name)))
  (if (string-match "\\`src/\\(.*\\.c\\)\\'" library)
      (find-function-C-source symbol (match-string 1 library) variable-p)
    (if (string-match "\\.el\\(c\\)\\'" library)
	(setq library (substring library 0 (match-beginning 1))))
    (let* ((filename (find-library-name library)))
      (with-current-buffer (find-file-noselect filename)
	(let ((regexp (format (if variable-p
				  find-variable-regexp
				find-function-regexp)
			      (regexp-quote (symbol-name symbol))))
	      (case-fold-search))
	  (with-syntax-table emacs-lisp-mode-syntax-table
	    (goto-char (point-min))
	    (if (or (re-search-forward regexp nil t)
		    (re-search-forward
		     (concat "^([^ ]+" find-function-space-re "['(]"
			     (regexp-quote (symbol-name symbol))
			     "\\>")
		     nil t))
		(progn
		  (beginning-of-line)
		  (cons (current-buffer) (point)))
	      (error "Cannot find definition of `%s' in library `%s'"
		     symbol library))))))))

;;;###autoload
(defun find-function-noselect (function)
  "Return a pair (BUFFER . POINT) pointing to the definition of FUNCTION.

Finds the Emacs Lisp library containing the definition of FUNCTION
in a buffer and the point of the definition.  The buffer is
not selected.

If the file where FUNCTION is defined is not known, then it is
searched for in `find-function-source-path' if non nil, otherwise
in `load-path'."
  (if (not function)
      (error "You didn't specify a function"))
  (and (subrp (symbol-function function))
       (error "%s is a primitive function" function))
  (let ((def (symbol-function function))
	aliases)
    (while (symbolp def)
      (or (eq def function)
	  (if aliases
	      (setq aliases (concat aliases
				    (format ", which is an alias for `%s'"
					    (symbol-name def))))
	    (setq aliases (format "`%s' an alias for `%s'"
				  function (symbol-name def)))))
      (setq function (symbol-function function)
	    def (symbol-function function)))
    (if aliases
	(message aliases))
    (let ((library
	   (cond ((eq (car-safe def) 'autoload)
		  (nth 1 def))
		 ((symbol-file function)))))
      (find-function-search-for-symbol function nil library))))

(defalias 'function-at-point 'function-called-at-point)

(defun find-function-read (&optional variable-p)
  "Read and return an interned symbol, defaulting to the one near point.

If the optional VARIABLE-P is nil, then a function is gotten
defaulting to the value of the function `function-at-point', otherwise
a variable is asked for, with the default coming from
`variable-at-point'."
  (let ((symb (funcall (if variable-p
			   'variable-at-point
			 'function-at-point)))
	(enable-recursive-minibuffers t)
	val)
    (if (equal symb 0)
	(setq symb nil))
    (setq val (if variable-p
		  (completing-read
		   (concat "Find variable"
			   (if symb
			       (format " (default %s)" symb))
			   ": ")
		   obarray 'boundp t nil)
		(completing-read
		 (concat "Find function"
			 (if symb
			     (format " (default %s)" symb))
			 ": ")
		 obarray 'fboundp t nil)))
    (list (if (equal val "")
	      symb
	    (intern val)))))

(defun find-function-do-it (symbol variable-p switch-fn)
  "Find Emacs Lisp SYMBOL in a buffer and display it.
If VARIABLE-P is nil, a function definition is searched for, otherwise
a variable definition is searched for.  The start of a definition is
centered according to the variable `find-function-recenter-line'.
See also `find-function-after-hook'  It is displayed with function SWITCH-FN.

Point is saved in the buffer if it is one of the current buffers."
  (let* ((orig-point (point))
	(orig-buf (window-buffer))
	(orig-buffers (buffer-list))
	(buffer-point (save-excursion
			(funcall (if variable-p
				      'find-variable-noselect
				    'find-function-noselect)
				  symbol)))
	(new-buf (car buffer-point))
	(new-point (cdr buffer-point)))
    (when buffer-point
      (when (memq new-buf orig-buffers)
	(push-mark orig-point))
      (funcall switch-fn new-buf)
      (goto-char new-point)
      (recenter find-function-recenter-line)
      (run-hooks 'find-function-after-hook))))

;;;###autoload
(defun find-function (function)
  "Find the definition of the FUNCTION near point.

Finds the Emacs Lisp library containing the definition of the function
near point (selected by `function-at-point') in a buffer and
places point before the definition.  Point is saved in the buffer if
it is one of the current buffers.

The library where FUNCTION is defined is searched for in
`find-function-source-path', if non nil, otherwise in `load-path'.
See also `find-function-recenter-line' and `find-function-after-hook'."
  (interactive (find-function-read))
  (find-function-do-it function nil 'switch-to-buffer))

;;;###autoload
(defun find-function-other-window (function)
  "Find, in another window, the definition of FUNCTION near point.

See `find-function' for more details."
  (interactive (find-function-read))
  (find-function-do-it function nil 'switch-to-buffer-other-window))

;;;###autoload
(defun find-function-other-frame (function)
  "Find, in ananother frame, the definition of FUNCTION near point.

See `find-function' for more details."
  (interactive (find-function-read))
  (find-function-do-it function nil 'switch-to-buffer-other-frame))

;;;###autoload
(defun find-variable-noselect (variable &optional file)
  "Return a pair `(BUFFER . POINT)' pointing to the definition of SYMBOL.

Finds the Emacs Lisp library containing the definition of SYMBOL
in a buffer and the point of the definition.  The buffer is
not selected.

The library where VARIABLE is defined is searched for in FILE or
`find-function-source-path', if non nil, otherwise in `load-path'."
  (if (not variable)
      (error "You didn't specify a variable"))
  ;; Fixme: I think `symbol-file' should be fixed instead.  -- fx
  (let ((library (or file (symbol-file (cons 'defvar variable)))))
    (find-function-search-for-symbol variable 'variable library)))

;;;###autoload
(defun find-variable (variable)
  "Find the definition of the VARIABLE near point.

Finds the Emacs Lisp library containing the definition of the variable
near point (selected by `variable-at-point') in a buffer and
places point before the definition.  Point is saved in the buffer if
it is one of the current buffers.

The library where VARIABLE is defined is searched for in
`find-function-source-path', if non nil, otherwise in `load-path'.
See also `find-function-recenter-line' and `find-function-after-hook'."
  (interactive (find-function-read 'variable))
  (find-function-do-it variable t 'switch-to-buffer))

;;;###autoload
(defun find-variable-other-window (variable)
  "Find, in another window, the definition of VARIABLE near point.

See `find-variable' for more details."
  (interactive (find-function-read 'variable))
  (find-function-do-it variable t 'switch-to-buffer-other-window))

;;;###autoload
(defun find-variable-other-frame (variable)
  "Find, in annother frame, the definition of VARIABLE near point.

See `find-variable' for more details."
  (interactive (find-function-read 'variable))
  (find-function-do-it variable t 'switch-to-buffer-other-frame))

;;;###autoload
(defun find-function-on-key (key)
  "Find the function that KEY invokes.  KEY is a string.
Point is saved if FUNCTION is in the current buffer."
  (interactive "kFind function on key: ")
  (let (defn)
    (save-excursion
      (let* ((event (and (eventp key) (aref key 0))) ; Null event OK below.
	     (start (event-start event))
	     (modifiers (event-modifiers event))
	     (window (and (or (memq 'click modifiers) (memq 'down modifiers)
			      (memq 'drag modifiers))
			  (posn-window start))))
	;; For a mouse button event, go to the button it applies to
	;; to get the right key bindings.  And go to the right place
	;; in case the keymap depends on where you clicked.
	(when (windowp window)
	  (set-buffer (window-buffer window))
	  (goto-char (posn-point start)))
	(setq defn (key-binding key))))
    (let ((key-desc (key-description key)))
      (if (or (null defn) (integerp defn))
	  (message "%s is unbound" key-desc)
	(if (consp defn)
	    (message "%s runs %s" key-desc (prin1-to-string defn))
	  (find-function-other-window defn))))))

;;;###autoload
(defun find-function-at-point ()
  "Find directly the function at point in the other window."
  (interactive)
  (let ((symb (function-at-point)))
    (when symb
      (find-function-other-window symb))))

;;;###autoload
(defun find-variable-at-point ()
  "Find directly the function at point in the other window."
  (interactive)
  (let ((symb (variable-at-point)))
    (when (and symb (not (equal symb 0)))
      (find-variable-other-window symb))))

;;;###autoload
(defun find-function-setup-keys ()
  "Define some key bindings for the find-function family of functions."
  (define-key ctl-x-map "F" 'find-function)
  (define-key ctl-x-4-map "F" 'find-function-other-window)
  (define-key ctl-x-5-map "F" 'find-function-other-frame)
  (define-key ctl-x-map "K" 'find-function-on-key)
  (define-key ctl-x-map "V" 'find-variable)
  (define-key ctl-x-4-map "V" 'find-variable-other-window)
  (define-key ctl-x-5-map "V" 'find-variable-other-frame))

(provide 'find-func)

;;; arch-tag: 43ecd81c-74dc-4d9a-8f63-a61e55670d64
;;; find-func.el ends here
