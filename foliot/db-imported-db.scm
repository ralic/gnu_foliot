;; -*- mode: scheme; coding: utf-8 -*-

;;;;
;;;; Copyright (C) 2011 - 2016
;;;; Free Software Foundation, Inc.

;;;; This file is part of Kisê.

;;;; Kisê is free software: you can redistribute it and/or modify it
;;;; under the terms of the GNU General Public License as published by
;;;; the Free Software Foundation, either version 3 of the License, or
;;;; (at your option) any later version.

;;;; Kisê is distributed in the hope that it will be useful, but
;;;; WITHOUT ANY WARRANTY; without even the implied warranty of
;;;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;;;; General Public License for more details.

;;;; You should have received a copy of the GNU General Public License
;;;; along with Kisê.  If not, see <http://www.gnu.org/licenses/>.
;;;;

;;; Commentary:

;;; Code:


(define-module (kise db-imported-db)
  #:use-module (ice-9 format)
  #:use-module (srfi srfi-1)
  #:use-module (grip reexport)
  #:use-module (grip do)
  #:use-module (grip db sqlite)
  #:use-module (grip dates)
  #:use-module (grip i18n)
  #:use-module (grip utils)
  #:use-module (grip strings)
  #:use-module (grip gnome colours)
  #:use-module (kise globals)
  #:use-module (kise db-con)

  #:export (db-idb/add-imported-db-table
	    db-idb/check-schema
	    db-idb/create-complete-table
	    db-idb/select-all
	    db-idb/select-some
	    db-idb/get
	    db-idb/set
	    db-idb/get-tuple
	    db-idb/update
	    db-idb/find-pos
	    db-idb/get-next-id
	    db-idb/add
	    db-idb/delete
	    db-idb/get-used-colour-set-ids
	    db-idb/get-unused-colour-set-ids
	    db-idb/get-colour-alist))


(eval-when (expand load eval)
  (re-export-public-interface (grip db sqlite)
			      (grip dates)
			      (grip i18n)
			      (grip utils)
			      (grip strings)
			      (kise globals)
			      (kise db-con))
  (textdomain "db-imported-db")
  (bindtextdomain "db-imported-db" (storage-get 'pofdir)))


;;;
;;; Globals
;;;

(define (db-idb/fields)
  (let ((sep "."))
    (format #f "id,
   name,
   strftime('%d~A%m~A%Y', imported_the, 'unixepoch'),
   imported_by,
   colour_set"
	    sep sep)))


;;;
;;; Attr pos, get, set
;;;

(define (db-idb/fields-offsets)
  '((id . 0)
    (name . 1) ;; it actually is the filename
    (filename . 1)
    (imported_the . 2)
    (imported_by . 3)
    (colour_set . 4)))

(define (db-idb/get-pos what)
  (assq-ref (db-idb/fields-offsets) what))

(define (db-idb/get db-tuple what)
  ;; db-tuple is a vector
  (vector-ref db-tuple (db-idb/get-pos what)))

(define (db-idb/set db-tuple what value)
  ;; db-tuple is a vector
  (vector-set! db-tuple (db-idb/get-pos what) value))

(define (db-idb/get-tuple tuples offset)
  ;; so far, tuples is a list
  (list-ref tuples offset))


;;;
;;; Create table
;;;

(define (db-idb/add-imported-db-table-str)
  "create table kise_imported_db (
     id               integer primary key not null,
     name             text,
     imported_the     integer,
     imported_by      text,
     colour_set       integer
);")

(define (db-idb/add-imported-db-table db)
  (sqlite/command db (db-idb/add-imported-db-table-str)))

(define (db-idb/check-schema db)
  ;; 'none, 'partial, 'complete
  (if (sqlite/table-exists? db "kise_imported_db")
      (let* ((table-info (sqlite/table-info db "kise_imported_db"))
	     (cols-nb (length table-info)))
	(cond ((= cols-nb 4) ;; colour_set column added - 2013/07/29
	       'partial)
	      ((= cols-nb 5)
	       'complete)))
      'none))

(define (db-idb/create-complete-table db)
  (if (sqlite/table-exists? db "kise_imported_db")
      ;; colour_set columns added - 2013/07/29
      (let* ((table-info (sqlite/table-info db "kise_imported_db"))
	     (cols-nb (length table-info)))
	(if (= cols-nb 4)
	    (begin
	      (sqlite/add-column db "kise_imported_db" "colour_set integer"))))
      (db-idb/add-imported-db-table db)))


;;;
;;; Select
;;;

(define (db-idb/select-one-str)
  "select *
     from kise_imported_db
    where id = '~A';")

(define (db-idb/select-one reference)
  (sqlite/query (db-con)
		(format #f "~?" (db-idb/select-one-str)
			(list reference))))

(define (db-idb/select-all-str)
  "select *
     from kise_imported_db
 order by name;")

(define (db-idb/select-all-for-display-str)
  "select ~A
     from kise_imported_db
 order by name;")

(define* (db-idb/select-all #:optional (display? #f))
  (if display?
      (sqlite/query (db-con) (format #f "~?" (db-idb/select-all-for-display-str)
				     (list (db-idb/fields))))
      (sqlite/query (db-con) (db-idb/select-all-str))))

(define (db-idb/select-some-str)
  "select *
     from kise_imported_db
    where ~A
 order by name;")

(define (db-idb/select-some where)
  (sqlite/query (db-con)
		(format #f "~?" (db-idb/select-some-str)
			(list where))))


;;;
;;; Updates
;;;

(define (db-idb/set-date-str)
  "update kise_imported_db
      set ~A = strftime('%s','~A')
    where id = '~A';")

(define (db-idb/set-str)
  "update kise_imported_db
      set ~A = '~A'
    where id = '~A';")

(define (db-idb/update db-tuple what value . displayed-value)
  (let* ((id (db-idb/get db-tuple 'id))
	 (sql-value (case what
		      ((filename) (str/prep-str-for-sql value))
		      (else
		       value)))
	 (sql-str (case what
		    ((imported_the) (db-idb/set-date-str))
		    (else
		     (db-idb/set-str))))
	 (cmd (format #f "~?" sql-str (list what sql-value id))))
    (sqlite/command (db-con) cmd)
    (if (null? displayed-value)
	(db-idb/set db-tuple what value)
	(db-idb/set db-tuple what (car displayed-value)))
    ;; updated? reordered?
    (values #t #f)))

(define (db-idb/find-pos tuples what value pred)
  (let ((its-length (length tuples))
	(accessor (if (symbol? what) db-idb/get vector-ref)))
    (and (> its-length 0)
	 (catch 'exit
	   (lambda ()
	     (do ((i 0 (1+ i)))
		 ((= i its-length) #f)
	       (let ((db-tuple (list-ref tuples i)))
		 (if (pred (accessor db-tuple what) value)
		     (throw 'exit i)))))
	   (lambda (key index)
	     index)))))


;;;
;;; Add
;;;

(define (db-idb/get-next-id-str)
  "select max(id) from kise_imported_db;")

(define (db-idb/get-next-id)
  (let* ((next (sqlite/query (db-con)
			     (db-idb/get-next-id-str)))
	 (value (vector-ref (car next) 0)))
    ;; (format #t "db-idb/get-next-id: ~S. value: ~S~%" next value)
    (if value (1+ value) 0)))

(define (db-idb/add-str)
  "insert into kise_imported_db (id,
                                 name,
                                 imported_the,
                                 imported_by,
                                 colour_set)
   values ('~A',
           '~A',
           strftime('%s', '~A'),
           '~A',
           '~A');")

(define* (db-idb/add filename date who cs-id #:optional (id #f))
  (let* ((next-id (or id (db-idb/get-next-id)))
	 (insert (format #f "~?" (db-idb/add-str)
			 (list next-id filename date who cs-id))))
    ;; (dimfi insert)
    (sqlite/command (db-con) insert)
    next-id))


;;;
;;; Delete
;;;

(define (db-idb/delete-str)
  "delete from kise_imported_db
    where id = '~A';")

(define (db-idb/delete reference)
  (sqlite/command (db-con)
		  (format #f "~?" (db-idb/delete-str)
			  (list reference))))


;;;
;;; Other
;;;

(define (db-idb/get-used-colour-set-ids)
  (filter-map (lambda (tuple) (db-idb/get tuple 'colour_set)) (db-idb/select-all)))

(define (db-idb/get-unused-colour-set-ids)
  (lset-difference = (colour-set-ids) (db-idb/get-used-colour-set-ids)))

(define (db-idb/get-colour-alist)
  (let ((alist (list)))
    (for-each (lambda (tuple)
		(let* ((id (db-idb/get tuple 'id))
		       (ics (db-idb/get tuple 'colour_set))
		       (ibg (colour-set-bg ics))
		       (ifg (colour-set-fg ics)))
		  (set! alist (assoc-set! alist id (cons ibg ifg)))))
	(db-idb/select-all))
    alist))


#!

(db-con/open "/usr/alto/db/sqlite.alto.tests.db")
(db-idb/select-all)

(db-idb/add "/usr/alto/db/sqlite.alto.christian.db" "2011-06-14" "david")
(db-idb/select-some "name like '%sqlite.alto.christian.db'")

!#