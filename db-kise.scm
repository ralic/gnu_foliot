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

(define-module (kise db-kise)
  ;; guile
  :use-module (ice-9 format)
  :use-module (ice-9 receive)
  :use-module (oop goops)

  ;; common
  :use-module (macros reexport)
  :use-module (macros when)
  :use-module (macros do)
  :use-module (system dates)
  :use-module (strings strings)
  :use-module (db sqlite)

  ;; kise
  :use-module (kise db-con)

  :export (db-kise/add-kise-table
	   db-kise/prepend-empty
	   db-kise/select-one
	   db-kise/select-all
	   db-kise/select-some
	   db-kise/select-another-some
	   db-kise/select-distinct
	   db-kise/get-pos
	   db-kise/get
	   db-kise/set
	   db-kise/get-tuple
	   db-kise/update
	   db-kise/find-pos
	   db-kise/get-next-id
	   db-kise/add
	   db-kise/duplicate
	   db-kise/delete))


(eval-when (compile load eval)
  (re-export-public-interface (db sqlite)
			      (system dates)
			      (strings strings)
			      (kise db-con)))


;;;
;;; Globals
;;;

(define (db-kise/fields)
  (let ((sep "."))
    (format #f "id,
   strftime('%d~A%m~A%Y', date_, 'unixepoch'),
   who,
   for_whom,
   duration,
   to_be_charged,
   charging_type,
   what,
   description,
   strftime('%d~A%m~A%Y', created_the, 'unixepoch'),
   created_by,
   strftime('%d~A%m~A%Y', modified_the, 'unixepoch'),
   modified_by"
	    sep sep sep sep sep sep)))


;;;
;;; Non api stuff
;;;

(define (db-kise/prepend-empty tuples . v-size)
  ;; tuples is a list AND, if there is an empty tuple, this function
  ;; assumes its pos is 0, otherwise it prepends tuples with an empty one
  (cond ((null? tuples)
	 (if (null? v-size)
	     (list #(""))
	     (list (make-vector (car v-size) ""))))
	(else
	 (let* ((tuple (list-ref tuples 0))
		(its-length (vector-length tuple))
		(empty-v (make-vector its-length "")))
	   (if (equal? tuple empty-v)
	       tuples
	       (cons empty-v tuples))))))

;;;
;;; Create table
;;;

(define (db-kise/add-kise-table-str)
  "create table kise (
     id             integer primary key not null,
     date_          integer,
     who            text,
     for_whom       text,
     duration       float,
     to_be_charged  text,
     charging_type  text,
     what           text,
     description    text,
     created_the    integer,
     created_by     text,
     modified_the   integer,
     modified_by    text
   );")

(define (db-kise/add-kise-table)
  (sqlite/command (db-con)  (db-kise/add-kise-table-str)))


;;;
;;; Select
;;;

(define (db-kise/select-one-str)
  "select ~A
     from kise
    where id='~A'")

(define (db-kise/select-one reference)
  (sqlite/query (db-con)
		(format #f "~?" (db-kise/select-one-str)
			(list (db-kise/fields)
			      reference))))

(define (db-kise/select-all-str)
  "select ~A
     from kise
 order by date_ desc, who asc, for_whom asc, what asc, id desc")

(define (db-kise/select-all . aggregate?)
  (let ((what (if (null? aggregate?) (db-kise/fields) (car aggregate?))))
    (sqlite/query (db-con)
		  (format #f "~?" (db-kise/select-all-str)
			  (list what)))))

(define (db-kise/select-some-str)
  "select ~A
     from kise
    where ~A
 order by date_ desc, who asc, for_whom asc, what asc, id desc")

(define (db-kise/select-some-with-ids-str)
  "select ~A
     from kise
    where ~A
       or id in ~A
 order by date_ desc, who asc, for_whom asc, what asc, id desc")

(define (db-kise/select-some where ids . aggregate?)
  (let ((what (if (null? aggregate?) (db-kise/fields) (car aggregate?))))
    (cond ((and where ids)
	   (sqlite/query (db-con)
			 (format #f "~?" (db-kise/select-some-with-ids-str)
				 (list what
				       where
				       (dbf/build-set-expression ids)
				       ))))
	  (where
	   (sqlite/query (db-con)
			 (format #f "~?" (db-kise/select-some-str)
				 (list what
				       where
				       ))))
	  (else
	   (if (null? aggregate?)
	       (db-kise/select-all)
	       (db-kise/select-all (car aggregate?))
	       )))))

(define (db-kise/select-another-some-str mode)
  (case mode
    ((1) "select ~A from kise where ~A group by ~A order by ~A")
    ((2) "select ~A from kise where ~A group by ~A")
    ((3) "select ~A from kise where ~A")
    ((4) "select ~A from kise where ~A order by ~A")
    ((5) "select ~A from kise group by ~A order by ~A")
    ((6) "select ~A from kise group by ~A")
    ((7) "select ~A from kise order by ~A")
    ((8) "select ~A from kise")))

(define (db-kise/select-another-some where group-by order-by)
  (let* ((mode (cond ((and where group-by order-by) 1)
		     ((and where group-by) 2)
		     ((and where order-by) 4)
		     (where 3)
		     ((and group-by order-by) 5)
		     (group-by 6)
		     (order-by 7)
		     (else
		      8)))
	 (query-string (format #f "~?" (db-kise/select-another-some-str mode)
			       (case mode
				 ((1) (list (db-kise/fields) where group-by order-by))
				 ((2) (list (db-kise/fields) where group-by))
				 ((3) (list (db-kise/fields) where))
				 ((4) (list (db-kise/fields) where order-by))
				 ((5) (list (db-kise/fields) group-by order-by))
				 ((6) (list (db-kise/fields) group-by))
				 ((7) (list (db-kise/fields) order-by))
				 ((8) (list (db-kise/fields)))))))
    (format #t "db-kise/select-another-some~%  ~S~%" query-string)
    (sqlite/query (db-con) query-string)))

(define (db-kise/select-distinct-str)
  "select distinct(~A) from kise order by ~A;")

(define (db-kise/select-distinct colname . add-empty?)
  ;; because the results of this function is also used to build combo,
  ;; we need the ability to add an empty entry id necessary.
  (let ((distincts (sqlite/query (db-con)
				 (format #f "~?" (db-kise/select-distinct-str)
					 (list colname colname)))))
    (if (null? add-empty?)
	distincts
	(db-kise/prepend-empty distincts))))


;;;
;;; Attr pos
;;;

(define (db-kise/fields-offsets)
  '((id . 0)
    (date_ . 1)
    (who . 2)
    (for_whom . 3)
    (duration . 4)
    (to_be_charged . 5)
    (charging_type . 6)
    (what . 7)
    (description . 8)
    (created_the . 9)
    (created_by . 10)
    (modified_the . 11)
    (modified_by . 12)))

(define (db-kise/get-pos what)
  (cdr (assoc what (db-kise/fields-offsets))))


;;;
;;; Later a global API
;;;

(define (db-kise/get db-tuple what)
  ;; db-tuple is a vector
  (vector-ref db-tuple (db-kise/get-pos what)))

(define (db-kise/set db-tuple what value)
  ;; db-tuple is a vector
  (vector-set! db-tuple (db-kise/get-pos what) value))

(define (db-kise/get-tuple tuples offset)
  ;; so far, tuples is a list
  (list-ref tuples offset))


;;;
;;; Updates
;;;

(define (db-kise/set-date-str)
  "update kise
      set ~A = strftime('%s','~A')
    where id = '~A';")

(define (db-kise/set-str)
  "update kise
      set ~A = '~A'
    where id = '~A';")

(define (db-kise/update db-tuple what value . displayed-value)
  (let* ((id (db-kise/get db-tuple 'id))
	 (sql-value (case what
		      ((who for_whom what description) (str/prep-str-for-sql value))
		      (else
		       value)))
	 (sql-str (case what
		    ((date_ created_the modified_the) (db-kise/set-date-str))
		    (else
		     (db-kise/set-str))))
	 (cmd (format #f "~?" sql-str (list what sql-value id))))
    ;; (format #t "~S~%Displayed value: ~S~%" cmd displayed-value)
    (sqlite/command (db-con) cmd)
    (if (null? displayed-value)
	(db-kise/set db-tuple what value)
	(db-kise/set db-tuple what (car displayed-value)))
    ;; updated? reordered?
    (values #t #f)))

(define (db-kise/find-pos tuples what value pred)
  (let ((its-length (length tuples))
	(accessor (if (symbol? what) db-kise/get vector-ref)))
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
;;; Add / Dupplcate
;;;

(define (db-kise/get-next-id-str)
  "select max(id) from kise;")

(define (db-kise/get-next-id)
  (let* ((next (sqlite/query (db-con)
			     (db-kise/get-next-id-str)))
	 (value (vector-ref (car next) 0)))
    ;; (format #t "db-kise/get-next-id: ~S. value: ~S~%" next value)
    (if value (1+ value) 0)))

(define (db-kise/add-str)
  "insert into kise (id,
                     date_,
                     who,
                     for_whom,
                     what,
                     duration,
                     to_be_charged,
                     description,
                     created_the,
                     created_by,
                     modified_the,
                     modified_by)
   values ('~A',
           strftime('%s','~A'),
           '~A',
           '~A',
           '~A',
           '~A',
           '~A',
           '~A',
           strftime('%s','~A'),
           '~A',
           strftime('%s','~A'),
           '~A')")

(define (db-kise/add date who for-whom what duration to-be-charged description . rests)
  (let* ((next-id (db-kise/get-next-id))
	 (created-the (if (null? rests) date (list-ref rests 0)))
	 (created-by (if (null? rests) who (list-ref rests 1)))
	 (modified-the (if (null? rests) date (list-ref rests 2)))
	 (modified-by (if (null? rests) who (list-ref rests 3)))
	 (insert (format #f "~?" (db-kise/add-str)
			 (list next-id
			       date
			       who
			       for-whom
			       what
			       duration
			       to-be-charged
			       description
			       created-the
			       created-by
			       modified-the
			       modified-by
			       ))))
    ;; (format #t "~S~%" insert)
    (sqlite/command (db-con) insert)
    next-id))

(define (db-kise/duplicate reference . tuple)
  (if (null? tuple)
      (set! tuple (car (db-kise/select-one reference)))
      (set! tuple (car tuple)))
  ;; date passed to add must be of type iso yyyy-mm-dd. the tuple has
  ;; them like 'dd-mm-yyyy' [till now.
  (let* ((today (date/system-date))
	 (iso-today (date/iso-date today))
	 (date (date/iso-date (db-kise/get tuple 'date_)))
	 (who (str/prep-str-for-sql (db-kise/get tuple 'who))))
    (db-kise/add date
		 who
		 (str/prep-str-for-sql (db-kise/get tuple 'for_whom))
		 (str/prep-str-for-sql (db-kise/get tuple 'what))
		 (db-kise/get tuple 'duration)
		 (db-kise/get tuple 'to_be_charged)
		 (str/prep-str-for-sql (db-kise/get tuple 'description))
		 iso-today
		 who
		 iso-today
		 who)))


;;;
;;; Delete
;;;

(define (db-kise/delete-str)
  "delete from kise
    where id = '~A';")

(define (db-kise/delete reference)
  (sqlite/command (db-con)
		  (format #f "~?" (db-kise/delete-str)
			  (list reference))))


#!

(use-modules (kise db-kise))
(reload-module (resolve-module '(kise db-kise)))

(db-con/open "/tmp/new.db")
(sqlite-close (db-con))

(db-kise/get-next-id)

(define tuples (db-kise/select-all))
(define tuple (db-kise/get-tuple tuples 1))

(define tl-widget tl-kwidget*)
(define tuple (ktlw/get-tuple tl-widget 1))

(db-kise/get tuple 'who)
(db-kise/set tuple 'description "another description")
(db-kise/set tuple 'date_ "2012-01-31")

(db-kise/update tuple 'date_ "2010-12-01")
(db-kise/update tuple 'date_ "2010-12-01")

(db-kise/find-pos tuples 'id 40 =)

(db-kise/add "2011-06-14"
	     "david"
	     ""
	     "" 	;; what 
	     0		;; duration
	     "f"	;; to-be-charged
	     "")	;; description

(db-kise/delete "44")
(db-kise/select-some "who = 'bibi'" #f "sum(duration)")


;;;
;;; SQL examples/tests
;;;

  select * 
    from kise 
   where what like '%email%' 
      or id in (41, 42, 43)
       ;

  select sum(duration)
    from kise 
   where for_whom like '%lpdi%' 
      or id in (100)
       ;

  select sum(duration)
    from kise 
   where for_whom like '%lpdi%'
     and to_be_charged = 't'
       ;

;; this filter

  select *
    from kise 
   where for_whom like '%lpdi%'
     and to_be_charged = 't'
      or id in (100, 101, 102)
       ;

;; can be used ^^ for the total time
;; --> BUT will need this query, below, for the charged time

  select sum(duration)
    from kise 
   where (for_whom like '%lpdi%' or id in (100, 101, 102))
     and to_be_charged = 't'
       ;

 update kise
    set date_ = '1246060800'
  where id = '40';

!#