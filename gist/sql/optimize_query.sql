-- I have code in a procedure and it is running away. let's fix it!
-- I need you to review the indexes and query below to determine what I need to do to make sure the oracle optimizer works for my query again
-- DO NOT EVALUATE THIS CODE DIRECTLY BELOW; I am ONLY running this find indexes on tables...
SELECT DISTINCT table_name,
                index_name,
                column_name,
                column_position
  FROM all_ind_columns
 WHERE lower(table_name) IN ('student_quizzes_gtt','student_quizzes','student_enrollments','quizzes','student_quiz_answers','quiz_questions_answers','assessment_question_banks')
   AND index_name NOT LIKE 'BIN$%'
 ORDER BY table_name,
          index_name,
          column_position;
-- my indexes that should be considered:
--     TABLE_NAME  INDEX_NAME  COLUMN_NAME COLUMN_POSITION
-- 1 ASSESSMENT_QUESTION_BANKS LAST_CHG_142382_IDX INSTANCE  1
-- 2 ASSESSMENT_QUESTION_BANKS LAST_CHG_142382_IDX ORDERID 2
-- 3 ASSESSMENT_QUESTION_BANKS PK1014710477798008835794164794  ID  1
-- 4 ASSESSMENT_QUESTION_BANKS PK1014710477798008835794164794  INSTANCE  2
-- 5 ASSESSMENT_QUESTION_BANKS SYS_C002903894  INSTANCE  1
-- 6 ASSESSMENT_QUESTION_BANKS SYS_C002903894  ID  2
-- 7 QUIZZES LAST_CHG_142408_IDX INSTANCE  1
-- 8 QUIZZES LAST_CHG_142408_IDX ORDERID 2
-- 9 QUIZZES PK6086627813580260529101594632  ID  1
-- 10  QUIZZES PK6086627813580260529101594632  INSTANCE  2
-- 11  QUIZZES QUIZZES_PK  SURROGATE_ID  1
-- 12  QUIZZES QUIZZES_UNIQUE_INDX QUIZ_ID 1
-- 13  QUIZZES QUIZZES_UNIQUE_INDX COURSE_SECTION_ID 2
-- 14  QUIZZES QUIZZES_UNIQUE_INDX INSTANCE  3
-- 15  QUIZZES SYS_C002903915  INSTANCE  1
-- 16  QUIZZES SYS_C002903915  ID  2
-- 17  QUIZ_QUESTIONS_ANSWERS  QUIZ_QUESTIONS_ANSWERS_PK SURROGATE_ID  1
-- 18  QUIZ_QUESTIONS_ANSWERS  QUIZ_QUESTIONS_ANSWERS_UNIQUE_INDX  INSTANCE  1
-- 19  QUIZ_QUESTIONS_ANSWERS  QUIZ_QUESTIONS_ANSWERS_UNIQUE_INDX  COURSE_SECTION_ID 2
-- 20  QUIZ_QUESTIONS_ANSWERS  QUIZ_QUESTIONS_ANSWERS_UNIQUE_INDX  QUIZ_ID 3
-- 21  QUIZ_QUESTIONS_ANSWERS  QUIZ_QUESTIONS_ANSWERS_UNIQUE_INDX  USER_ID 4
-- 22  QUIZ_QUESTIONS_ANSWERS  QUIZ_QUESTIONS_ANSWERS_UNIQUE_INDX  QUESTION_ID 5
-- 23  QUIZ_QUESTIONS_ANSWERS  QUIZ_QUESTIONS_ANSWERS_UNIQUE_INDX  ANSWER_ID 6
-- 24  STUDENT_ENROLLMENTS STUDENT_ENROLLMENTS_IDX1  TERM_CODE 1
-- 25  STUDENT_ENROLLMENTS STUDENT_ENROLLMENTS_IDX1  CRN 2
-- 26  STUDENT_ENROLLMENTS STUDENT_ENROLLMENTS_IDX1  PIDM  3
-- 27  STUDENT_ENROLLMENTS STUDENT_ENROLLMENTS_IDX2  INSTANCE  1
-- 28  STUDENT_ENROLLMENTS STUDENT_ENROLLMENTS_IDX2  TERM_CODE 2
-- 29  STUDENT_ENROLLMENTS STUDENT_ENROLLMENTS_IDX2  PARTITION 3
-- 30  STUDENT_ENROLLMENTS STUDENT_ENROLLMENTS_IDX3  INSTANCE  1
-- 31  STUDENT_ENROLLMENTS STUDENT_ENROLLMENTS_IDX4  PARTITION 1
-- 32  STUDENT_ENROLLMENTS STUDENT_ENROLLMENTS_IDX5  TERM_CODE 1
-- 33  STUDENT_ENROLLMENTS STUDENT_ENROLLMENTS_UNIQUE_INDX INSTANCE  1
-- 34  STUDENT_ENROLLMENTS STUDENT_ENROLLMENTS_UNIQUE_INDX COURSE_SECTION_ID 2
-- 35  STUDENT_ENROLLMENTS STUDENT_ENROLLMENTS_UNIQUE_INDX USER_ID 3
-- 36  STUDENT_QUIZZES STUDENT_QUIZZES_PK  SURROGATE_ID  1
-- 37  STUDENT_QUIZZES STUDENT_QUIZZES_UNIQUE_INDX COURSE_SECTION_ID 1
-- 38  STUDENT_QUIZZES STUDENT_QUIZZES_UNIQUE_INDX USER_ID 2
-- 39  STUDENT_QUIZZES STUDENT_QUIZZES_UNIQUE_INDX QUIZ_ID 3
-- 40  STUDENT_QUIZZES STUDENT_QUIZZES_UNIQUE_INDX QUESTION_ID 4
-- 41  STUDENT_QUIZZES STUDENT_QUIZZES_UNIQUE_INDX ANSWER_ID 5
-- 42  STUDENT_QUIZZES STUDENT_QUIZZES_UNIQUE_INDX INSTANCE  6
-- 43  STUDENT_QUIZ_ANSWERS  STUDENT_QUIZ_ANSWERS_PK SURROGATE_ID  1
-- 44  STUDENT_QUIZ_ANSWERS  STUDENT_QUIZ_ANSWERS_UNIQUE_INDX  COURSE_SECTION_ID 1
-- 45  STUDENT_QUIZ_ANSWERS  STUDENT_QUIZ_ANSWERS_UNIQUE_INDX  USER_ID 2
-- 46  STUDENT_QUIZ_ANSWERS  STUDENT_QUIZ_ANSWERS_UNIQUE_INDX  QUIZ_ID 3
-- 47  STUDENT_QUIZ_ANSWERS  STUDENT_QUIZ_ANSWERS_UNIQUE_INDX  QUESTION_ID 4
-- 48  STUDENT_QUIZ_ANSWERS  STUDENT_QUIZ_ANSWERS_UNIQUE_INDX  ANSWER_ID 5
-- 49  STUDENT_QUIZ_ANSWERS  STUDENT_QUIZ_ANSWERS_UNIQUE_INDX  INSTANCE  6

-- now, this my query that is the problem...
-- using this EXPLAIN PLAN and consider the current indexes to help the oracle optimizer fix this query:
EXPLAIN PLAN FOR
INSERT INTO utl_d_lms.student_quizzes_gtt
(control_state,
 course_section_id,
 user_id,
 quiz_id,
 assignment_id,
 assignment_group_id,
 question_id,
 answer_id,
 title,
 submission_types,
 scoring_policy,
 show_correct_answers,
 show_correct_answers_last_attempt,
 shuffle_answers,
 question_title,
 question,
 answer,
 weight,
 points_possible,
 time_limit,
 allowed_attempts,
 question_count,
 correct,
 points,
 due_date,
 workflow_state,
 instance,
 activity_date,
 submission_id,
 foundational_skill,
 updated_date,
 term_code,
 quiz_version,
 started_date,
 finished_date,
 end_date,
 quiz_score,
 quiz_points_possible,
 position)
SELECT CASE
       WHEN src.course_section_id IS NOT NULL
            AND tgt.course_section_id IS NULL THEN
        'INSERT' -- new record to source, add to table
       WHEN src.course_section_id IS NOT NULL
            AND tgt.course_section_id IS NOT NULL THEN
        'UPDATE' -- record exists in both places
       END AS control_state,
       src.course_section_id,
       src.user_id,
       src.quiz_id,
       src.assignment_id,
       src.assignment_group_id,
       src.question_id,
       src.answer_id,
       src.title,
       src.submission_types,
       src.scoring_policy,
       src.show_correct_answers,
       src.show_correct_answers_last_attempt,
       src.shuffle_answers,
       src.question_title,
       src.question,
       src.answer,
       src.weight,
       src.points_possible,
       src.time_limit,
       src.allowed_attempts,
       src.question_count,
       src.correct,
       src.points,
       src.due_date,
       src.workflow_state,
       src.instance,
       SYSDATE AS activity_date,
       src.submission_id,
       src.foundational_skill,
       src.updated_date,
       src.term_code,
       src.quiz_version,
       src.started_date,
       src.finished_date,
       src.end_date,
       src.quiz_score,
       src.quiz_points_possible,
       src.position
  FROM (SELECT qd.course_section_id,
               sqa.user_id,
               qd.quiz_id,
               qd.assignment_id,
               qd.assignment_group_id,
               sqa.submission_id,
               sqa.question_id,
               sqa.answer_id,
               qd.title,
               qd.submission_types,
               qd.scoring_policy,
               qd.show_correct_answers,
               qd.show_correct_answers_last_attempt,
               qd.shuffle_answers,
               qqa.question_title,
               qqa.question,
               qqa.answer,
               qqa.weight,
               qqa.points_possible,
               qd.time_limit,
               qd.allowed_attempts,
               qd.question_count,
               sqa.correct,
               sqa.points,
               qd.due_date,
               caqb.title AS foundational_skill,
               sqa.workflow_state,
               'L2CAN' AS instance,
               sqa.updated_date,
               se.term_code,
               sqa.quiz_version,
               sqa.started_date,
               sqa.finished_date,
               sqa.end_date,
               sqa.quiz_score,
               sqa.quiz_points_possible,
               qqa.position
          FROM utl_d_lms.student_enrollments se
          JOIN utl_d_lms.quizzes qd
            ON qd.instance = se.instance
           AND qd.course_section_id = se.course_section_id
           AND se.instance = 'L2CAN'
           AND se.term_code = '202540'
           AND se.partition = 0
          JOIN utl_d_lms.student_quiz_answers sqa
            ON sqa.instance = qd.instance
           AND sqa.course_section_id = qd.course_section_id
           AND sqa.quiz_id = qd.quiz_id
           AND sqa.user_id = se.user_id
          LEFT JOIN utl_d_lms.quiz_questions_answers qqa
            ON qqa.instance = qd.instance
           AND qqa.course_section_id = qd.course_section_id
           AND qqa.quiz_id = qd.quiz_id
           AND qqa.user_id = se.user_id
           AND qqa.question_id = sqa.question_id
           AND qqa.answer_id = sqa.answer_id
          LEFT JOIN zcanvas_data.assessment_question_banks caqb
            ON caqb.instance = qd.instance
           AND caqb.context_id = se.course_id
           AND caqb.id = qqa.assessment_question_bank_id) src
  LEFT JOIN utl_d_lms.student_quizzes tgt
    ON tgt.instance = src.instance
   AND tgt.course_section_id = src.course_section_id
   AND tgt.quiz_id = src.quiz_id
   AND tgt.user_id = src.user_id
   AND tgt.question_id = src.question_id
   AND tgt.answer_id = src.answer_id
 WHERE 1 = 1 -- get anything more recent or new
   AND (src.updated_date > tgt.updated_date OR tgt.updated_date IS NULL);

-- running this will give us the explain plan output;  run, copy, paste
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);
-- here is the explain plan for my problem query... 
-- 1 Plan hash value: 764826008
-- 2  -- **WHAT THIS PLAN IS NOT SHOWING IS THAT A LOT OF TEMP SPACE IS BEING USED AND THAT IS WHEN IT ERRORS**
-- 3 -----------------------------------------------------------------------------------------------------------------------------------------
-- 4 | Id  | Operation                           | Name                      | Rows  | Bytes |TempSpc| Cost (%CPU)| Time     | Pstart| Pstop |
-- 5 -----------------------------------------------------------------------------------------------------------------------------------------
-- 6 |   0 | INSERT STATEMENT                    |                           |   155K|  1721M|       |   124K  (6)| 00:00:05 |       |       |
-- 7 |   1 |  LOAD TABLE CONVENTIONAL            | STUDENT_QUIZZES_GTT       |       |       |       |            |          |       |       |
-- 8 |   2 |   SEQUENCE                          | ISEQ$$_34708826           |       |       |       |            |          |       |       |
-- 9 |*  3 |    FILTER                           |                           |       |       |       |            |          |       |       |
-- 10  |*  4 |     HASH JOIN RIGHT OUTER           |                           |   155K|  1721M|  3233M|   124K  (6)| 00:00:05 |       |       |
-- 11  |   5 |      PARTITION LIST ALL             |                           |    59M|  2552M|       | 19467  (10)| 00:00:01 |     1 |    28 |
-- 12  |   6 |       TABLE ACCESS STORAGE FULL     | STUDENT_QUIZZES           |    59M|  2552M|       | 19467  (10)| 00:00:01 |     1 |    28 |
-- 13  |   7 |      VIEW                           |                           |   310K|  3428M|       | 83266   (6)| 00:00:04 |       |       |
-- 14  |*  8 |       HASH JOIN OUTER               |                           |   310K|   165M|   154M| 83266   (6)| 00:00:04 |       |       |
-- 15  |*  9 |        HASH JOIN OUTER              |                           |   310K|   150M|    83M| 79160   (6)| 00:00:04 |       |       |
-- 16  |* 10 |         HASH JOIN                   |                           |   310K|    79M|   379M| 16511  (12)| 00:00:01 |       |       |
-- 17  |* 11 |          TABLE ACCESS STORAGE FULL  | QUIZZES                   |  3060K|   344M|       |   904   (8)| 00:00:01 |       |       |
-- 18  |* 12 |          HASH JOIN                  |                           |  6278K|   910M|       | 11252  (17)| 00:00:01 |       |       |
-- 19  |* 13 |           TABLE ACCESS STORAGE FULL | STUDENT_ENROLLMENTS       | 34891 |  1192K|       |  3756   (7)| 00:00:01 |       |       |
-- 20  |  14 |           PARTITION LIST ALL        |                           |    61M|  6914M|       |  7293  (19)| 00:00:01 |     1 |    28 |
-- 21  |* 15 |            TABLE ACCESS STORAGE FULL| STUDENT_QUIZ_ANSWERS      |    61M|  6914M|       |  7293  (19)| 00:00:01 |     1 |    28 |
-- 22  |  16 |         PARTITION LIST ALL          |                           |    58M|    13G|       | 17658   (9)| 00:00:01 |     1 |    28 |
-- 23  |* 17 |          TABLE ACCESS STORAGE FULL  | QUIZ_QUESTIONS_ANSWERS    |    58M|    13G|       | 17658   (9)| 00:00:01 |     1 |    28 |
-- 24  |* 18 |        TABLE ACCESS STORAGE FULL    | ASSESSMENT_QUESTION_BANKS |  5570K|   260M|       |  2558   (7)| 00:00:01 |       |       |
-- 25  -----------------------------------------------------------------------------------------------------------------------------------------
-- 26   
-- 27  Predicate Information (identified by operation id):
-- 28  ---------------------------------------------------
-- 29   
-- 30     3 - filter("SRC"."UPDATED_DATE">"TGT"."UPDATED_DATE" OR "TGT"."UPDATED_DATE" IS NULL)
-- 31     4 - access("TGT"."INSTANCE"(+)="SRC"."INSTANCE" AND "TGT"."COURSE_SECTION_ID"(+)="SRC"."COURSE_SECTION_ID" AND 
-- 32                "TGT"."QUIZ_ID"(+)="SRC"."QUIZ_ID" AND "TGT"."USER_ID"(+)="SRC"."USER_ID" AND "TGT"."QUESTION_ID"(+)="SRC"."QUESTION_ID" AND 
-- 33                "TGT"."ANSWER_ID"(+)="SRC"."ANSWER_ID")
-- 34     8 - access("CAQB"."INSTANCE"(+)="QD"."INSTANCE" AND "CAQB"."CONTEXT_ID"(+)="SE"."COURSE_ID" AND 
-- 35                "CAQB"."ID"(+)="QQA"."ASSESSMENT_QUESTION_BANK_ID")
-- 36     9 - access("QQA"."INSTANCE"(+)="QD"."INSTANCE" AND "QQA"."COURSE_SECTION_ID"(+)="QD"."COURSE_SECTION_ID" AND 
-- 37                "QQA"."QUIZ_ID"(+)="QD"."QUIZ_ID" AND "QQA"."USER_ID"(+)="SE"."USER_ID" AND "QQA"."QUESTION_ID"(+)="SQA"."QUESTION_ID" AND 
-- 38                "QQA"."ANSWER_ID"(+)="SQA"."ANSWER_ID")
-- 39    10 - access("SQA"."INSTANCE"="QD"."INSTANCE" AND "SQA"."COURSE_SECTION_ID"="QD"."COURSE_SECTION_ID" AND 
-- 40                "SQA"."QUIZ_ID"="QD"."QUIZ_ID" AND "QD"."INSTANCE"="SE"."INSTANCE" AND "QD"."COURSE_SECTION_ID"="SE"."COURSE_SECTION_ID")
-- 41    11 - storage("QD"."INSTANCE"='L2CAN')
-- 42         filter("QD"."INSTANCE"='L2CAN')
-- 43    12 - access("SQA"."USER_ID"="SE"."USER_ID")
-- 44    13 - storage("SE"."TERM_CODE"='202540' AND "SE"."PARTITION"=0 AND "SE"."INSTANCE"='L2CAN')
-- 45         filter("SE"."TERM_CODE"='202540' AND "SE"."PARTITION"=0 AND "SE"."INSTANCE"='L2CAN')
-- 46    15 - storage("SQA"."INSTANCE"='L2CAN')
-- 47         filter("SQA"."INSTANCE"='L2CAN')
-- 48    17 - storage("QQA"."INSTANCE"(+)='L2CAN')
-- 49         filter("QQA"."INSTANCE"(+)='L2CAN')
-- 50    18 - storage("CAQB"."INSTANCE"(+)='L2CAN')
-- 51         filter("CAQB"."INSTANCE"(+)='L2CAN')
-- 52   
-- 53  Note
-- 54  -----
-- 55     - dynamic statistics used: dynamic sampling (level=4)
-- 56     - this is an adaptive plan
