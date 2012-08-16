
#ifndef nonogram_HEADER
#define nonogram_HEADER


#include <stdio.h>
#include <stdlib.h>
#include <stddef.h>
#include <time.h>
#include <string.h>

#ifndef false
#define false 0
#endif
#ifndef true
#define true 1
#endif


  /******* cell representation *******/

typedef unsigned char nonogram_cell;


#undef nonogram_BLANK
#undef nonogram_DOT
#undef nonogram_SOLID
#undef nonogram_BOTH
#define nonogram_BLANK  '\00'
#define nonogram_DOT    '\01'
#define nonogram_SOLID  '\02'
#define nonogram_BOTH   '\03'


  /******* puzzle representation *******/

  typedef unsigned long nonogram_sizetype;

#define nonogram_PRIuSIZE "lu"
#define nonogram_PRIoSIZE "lo"
#define nonogram_PRIxSIZE "lx"
#define nonogram_PRIXSIZE "lX"

  typedef struct nonogram_puzzle nonogram_puzzle;

  /******* solver state ******/

  typedef struct nonogram_solver nonogram_solver;

  int nonogram_initsolver(nonogram_solver *);
  int nonogram_termsolver(nonogram_solver *);

  int nonogram_load(nonogram_solver *c,
		    const nonogram_puzzle *puzzle,
		    nonogram_cell *grid, int remcells);
  int nonogram_unload(nonogram_solver *c);

  int nonogram_setlog(nonogram_solver *c,
		      FILE *logfile, int indent, int level);


  /******* solver activity *******/

#define nonogram_setlinelim(C,N) ((C)->cycles = (N))
  int nonogram_runsolver_n(nonogram_solver *c, int *tries);
  int nonogram_runlines_tries(nonogram_solver *c, int *lines, int *cycles);
  int nonogram_runlines_until(nonogram_solver *c, int *lines, clock_t lim);
  int nonogram_runcycles_tries(nonogram_solver *c, int *cycles);
  int nonogram_runcycles_until(nonogram_solver *c, clock_t lim);
  enum { /* return codes for above calls */
    nonogram_UNLOADED = 0,
    nonogram_FINISHED = 1,
    nonogram_UNFINISHED = 2,
    nonogram_FOUND = 4,
    nonogram_LINE = 8
  };

  /******* verbose solution *******/

  struct nonogram_point { size_t x, y; };
  struct nonogram_rect { struct nonogram_point min, max; };



#define nonogram_limitrow(S,R,X,F) \
  ((R) < (S)->puzzle->height ? (X) : (F))
#define nonogram_limitcol(S,C,X,F) \
  ((C) < (S)->puzzle->width ? (X) : (F))

  /* check what work needs to be done for a particular line */
#define nonogram_getrowmark(S,R) \
  nonogram_limitrow((S),(R),(S)->rowflag?(S)->rowflag[R]:0,0)
#define nonogram_getcolmark(S,C) \
  nonogram_limitcol((S),(C),(S)->colflag?(S)->colflag[C]:0,0)

  /* check if a line is being worked on */
#define nonogram_getrowfocus(S,R) \
  nonogram_limitrow((S),(R),(S)->on_row && \
  (S)->focus && (S)->lineno == (R),false)
#define nonogram_getcolfocus(S,C) \
  nonogram_limitcol((S),(C),!(S)->on_row && \
  (S)->focus && (S)->lineno == (C),false)


  /******* line-solver characteristics *******/

  typedef unsigned int nonogram_level;


  /* greatest dimensions of the puzzle */
  struct nonogram_lim {
    size_t maxline, maxrule;
  };

  /* size of each allocated block of shared workspace */
  struct nonogram_req {
    size_t byte, ptrdiff, size, nonogram_size, cell;
  };

  /* pointers to each block of shared workspace */
  struct nonogram_ws {
    void *byte;
    ptrdiff_t *ptrdiff;
    size_t *size;
    nonogram_sizetype *nonogram_size;
    nonogram_cell *cell;
  };

  struct nonogram_initargs {
    int *fits;
    struct nonogram_log *log;
    const nonogram_sizetype *rule;
    const nonogram_cell *line;
    nonogram_cell *result;
    size_t linelen, rulelen;
    ptrdiff_t linestep, rulestep, resultstep;
  };

  typedef void nonogram_prepproc(void *, const struct nonogram_lim *,
				 struct nonogram_req *);
  typedef int nonogram_initproc(void *, struct nonogram_ws *ws,
				const struct nonogram_initargs *);
  typedef int nonogram_stepproc(void *, void *ws);
  typedef void nonogram_termproc(void *);

  /* init and step return true if step should be called (again) */
  struct nonogram_linesuite {
    nonogram_prepproc *prep; /* indicate workspace requirements */
    nonogram_initproc *init; /* initialise for a particular line */
    nonogram_stepproc *step; /* perform a single step */
    nonogram_termproc *term; /* terminate line-processing */
  };


  nonogram_level nonogram_getlinesolvers(nonogram_solver *c);



  /* Push blocks as far towards the start of the array as they will
     go.  Return 0 if they won't go, or 1 if they will.

     line[0]..line[(linelen-1)*linestep] provides the current state of
     the line.

     rule[0]..rule[(rulelen-1)*rulestep] defines the rule for the
     line.

     The resultant positions will be written to
     pos[0]..pos[(rulelen-1)*posstep].

     solid[0]..solid[rulelen-1] are used as workspace.  Each contains
     the index of the left-most solid covered by the corresponding
     block, or -1 if no solid is covered.

     Internal workings will be written to log (if not NULL), and level
     is sufficiently high, indented by the specified amount.  */
  int nonogram_push(const nonogram_cell *line,
		    size_t linelen, ptrdiff_t linestep,
		    const nonogram_sizetype *rule,
		    size_t rulelen, ptrdiff_t rulestep,
		    nonogram_sizetype *pos, ptrdiff_t posstep,
		    ptrdiff_t *solid, FILE *log, int level, int indent);


  /******* 'fcomp (fast-complete)' line solver *******/

  extern const struct nonogram_linesuite nonogram_fcompsuite;
  typedef struct nonogram_fastwork nonogram_fcompwork;
  typedef struct nonogram_fastconf nonogram_fcompconf;


  /******* Miscellaneous *******/
#define nonogram_puzzlewidth(P) ((const size_t) (P)->width)
#define nonogram_puzzleheight(P) ((const size_t) (P)->height)


  extern const char *const nonogram_date;
  extern unsigned long const nonogram_loglevel;
  extern unsigned long const nonogram_maxrule;


  /******* private types and functions *******/

  typedef unsigned char nonogram_bool;



  enum {
    nonogram_EMPTY,   /* processing, but not on line */
    nonogram_WORKING, /* currently on a line */
    nonogram_DONE     /* line processing completed */
  };

  typedef struct {
    int score, dot, solid;
  } nonogram_lineattr;

  typedef struct nonogram_stack {
    struct nonogram_stack *next;
    nonogram_cell *grid;
    struct nonogram_rect editarea;
    struct nonogram_point pos;
    nonogram_lineattr *rowattr, *colattr;
    int remcells, level;
  } nonogram_stack;

  struct nonogram_lsnt {
    void *context;
    const char *name;
    const struct nonogram_linesuite *suite;
  };

  struct nonogram_solver {
    void *client_data;
    const struct nonogram_client *client;

    void *display_data;
    const struct nonogram_display *display;
    struct nonogram_rect editarea; /* temporary workspace */

    struct nonogram_ws workspace;
    struct nonogram_lsnt *linesolver; /* an array of length 'levels' */
    nonogram_level levels;

    nonogram_cell first; /* configured first guess; should be
                              replaced with choice based on remaining
                              unaccounted cells */
    int cycles; /* could be part of complete context */

    const nonogram_puzzle *puzzle;
    struct nonogram_lim lim;
    nonogram_cell *work;
    nonogram_lineattr *rowattr, *colattr;
    nonogram_level *rowflag, *colflag;

    nonogram_bool *rowdir, *coldir; /* to be removed */

    nonogram_stack *stack; /* pushed guesses */
    nonogram_cell *grid;
    int remcells, reminfo;

    /* (on_row,lineno) == line being solved */
    /* status == EMPTY => no line */
    /* status == WORKING => line being solved */
    /* status == DONE => line solved */
    /* focus => used by display */
    int fits, lineno;
    nonogram_level level;
    unsigned on_row : 1, focus : 1, status : 2, reversed : 1, alloc : 1;

    /* logfile */

  };

  struct nonogram_rule {
    size_t len;
    nonogram_sizetype *val;
  };

  struct nonogram_tn {
    struct nonogram_tn *c[2];
    char *n, *v;
  };

  struct nonogram_puzzle {
    struct nonogram_rule *row, *col;
    size_t width, height;
#if false
    char *title;
#endif
    struct nonogram_tn *notes;
  };

#define nonogram_NULLPUZZLE { 0, 0, 0, 0, 0 }


#endif // if define


