;; -*- mode: scheme; coding: utf-8 -*-

;;;; Copyright (C) 2011, 2012
;;;; Free Software Foundation, Inc.
;;;;
;;;; This library is free software; you can redistribute it and/or
;;;; modify it under the terms of the GNU Lesser General Public
;;;; License as published by the Free Software Foundation; either
;;;; version 3 of the License, or (at your option) any later version.
;;;; 
;;;; This library is distributed in the hope that it will be useful,
;;;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;;;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;;;; Lesser General Public License for more details.
;;;; 
;;;; You should have received a copy of the GNU Lesser General Public
;;;; License along with this library; if not, write to the Free Software
;;;; Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
;;;;

;;; Commentary:

;;; Code:

(define-module (kise connect)
  ;; guile/guile-gnome
  :use-module (oop goops)
  :use-module (gnome gobject)
  :use-module (gnome gtk)

  ;; common
  ;; :use-module (macros reexport)
  :use-module (gtk all)
  :use-module (system i18n)
  :use-module (macros when)

  ;; kise
  :use-module (kise db)
  :use-module (kise tl-widget)
  :use-module (kise config)
  :use-module (kise c-dialog)

  :duplicates (merge-generics 
	       replace
	       warn-override-core
	       warn
	       last)

  :export (kc/select-gui))


#!
(eval-when (compile load eval)
  (re-export-public-interface (oop goops)
			      (gnome gobject)
			      (gnome gtk)

			      (gtk all)
			      (system i18n)

			      (kise db)
			      (kise tl-widget)
			      (kise config)
			      (kise c-dialog)))
!#


;;;
;;; Globals
;;;


;;;
;;; API
;;;

(define (kc/connect-cant-connect-str)
  (_ "Some problem occured while trying to open ~A. It could be that you don't have writing permissions over it, or that it is not a Kisê database file. Please check all of the above and start again or create/connect to another Kisê database."))

(define (kc/connect-cant-create-str)
  (_ "You don't have 'writing permissions' in this directory: ~A. Please check your permissions and try again or make another directory selection."))

(define (kc/connect-create-exists-str)
  (_ "A file named ~A already exists. Please select another name or another directory."))

(define (kc/connect tl-widget kc-widget)
  (let* ((kc-dialog (dialog kc-widget))
	 (filename (get-filename kc-dialog))
	 (reuse-db? (get-active (reuse-db-cb kc-widget))))
    ;; (format #t "kc/connect: ~S ~S ~S~%" (mode kc-widget) filename reuse-db?)
    (case (mode kc-widget)
      ((open)
       ;; the user could select a 'wrong file'. all checks must be
       ;; done but 'exists
       (let ((checks-result (ktlw/open-db-checks filename)))
	 (case checks-result
	   ((wrong-perm not-an-sqlite-file)
	    (md1b/select-gui (dialog tl-widget)
			     (_ "Warning!")
			     (_ "DB connection problem:")
			     (format #f "~?" (kc/connect-cant-connect-str) (list filename))
			     (lambda () 'nothing)))
	   ((opened opened-partial-schema opened-no-schema)
	    (ktlw/open-db tl-widget filename 'from-gui 'open reuse-db? checks-result)
	    (set-modal kc-dialog #f)
	    (hide kc-dialog)))))
      ((create)
       ;; for some very obscure reasons, when in 'create' mode,
       ;; kc/connect is called 2x ... see kise-bugs for details.
       ;; (format #t "modal?: ~S // New db for kise in ~A~%" (get-modal kc-dialog) filename)
       (when (get-modal kc-dialog)
	 (let ((checks-result (ktlw/create-db-checks filename)))
	   (case checks-result
	     ((exists)
	      (md1b/select-gui (dialog tl-widget)
			       (_ "Warning!")
			       (_ "DB creation problem:")
			       (format #f "~?" (kc/connect-create-exists-str) (list (basename filename)))
			       (lambda () 'nothing)))
	     ((wrong-perm)
	      (md1b/select-gui (dialog tl-widget)
			       (_ "Warning!")
			       (_ "DB creation problem:")
			       (format #f "~?" (kc/connect-cant-create-str) (list (dirname filename)))
			       (lambda () 'nothing)))
	     ((ok opened)
	      (ktlw/open-db tl-widget filename 'from-gui 'create reuse-db? checks-result)
	      (set-modal kc-dialog #f)
	      (hide kc-dialog)))))))))

(define (kc/select-gui tl-widget)
  (let* ((parent (dialog tl-widget))
	 (g-file (glade-file tl-widget))
	 (db-file (kcfg/get 'db-file))
	 (reuse-db? (or (not db-file) (kcfg/get 'open-at-startup)))
	 (kc-widget (kc/make-dialog parent g-file))
	 (kc-dialog (dialog kc-widget)))
    ;; (format #t "Connecting Widget: ~S~%Parent: ~S~%Connecting Dialog: ~S~%" 
    ;; kc-widget parent kc-dialog)
    (if reuse-db?
	(set-active (reuse-db-cb kc-widget) #t))
    (if db-file
	;;(set-current-folder kc-dialog (dirname db-file))
	(select-filename kc-dialog db-file)
	(set-current-folder kc-dialog (sys/get 'udir)))
    ;; this is not allowed in 'open mode, which is the default
    ;; (if fname (set-current-name kc-dialog fname))
    (connect (ok-bt kc-widget)
	     'clicked
	     (lambda (button) 
	       (kc/connect tl-widget kc-widget)))
    (connect (cancel-bt kc-widget)
	     'clicked
	     (lambda (button) 
	       (set-modal kc-dialog #f)
	       (hide kc-dialog)))
    (set-modal kc-dialog #t)
    (show kc-dialog)))


#!

(use-modules (kise connect))
(reload-module (resolve-module '(kise connect)))
,m (kise connect)

(define tl-widget (make <kise/tl-widget>
		    :glade-file (aglobs/get 'gladefile)))
(kc/select-gui tl-widget "/usr/alto/db" "sqlite.alto.db")

(define c-widget (kc/make-dialog (dialog tl-widget) (aglobs/get 'gladefile)))
(dialog tl-widget)
(dialog c-widget)

!#