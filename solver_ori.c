/*
 *  Nonolib - Nonogram-solver library
 *  Copyright (C) 2001,5-7  Steven Simpson
 *
 *  This library is free software; you can redistribute it and/or
 *  modify it under the terms of the GNU Lesser General Public
 *  License as published by the Free Software Foundation; either
 *  version 2.1 of the License, or (at your option) any later version.
 *
 *  This library is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 *  Lesser General Public License for more details.
 *
 *  You should have received a copy of the GNU Lesser General Public
 *  License along with this library; if not, write to the Free Software
 *  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 *
 *  Contact Steven Simpson <ss@comp.lancs.ac.uk>
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>

#include "nonogram.h"
///#include "internal.h"

#ifndef nonogram_LOGLEVEL
#define nonogram_LOGLEVEL 1
#endif

static void makescore(nonogram_lineattr *attr,
		      const struct nonogram_rule *rule, int len);

static void setupstep(nonogram_solver *);
static void step(nonogram_solver *);

/* Returns true if a change was detected. */
static int redeemstep(nonogram_solver *c);

static int nonogram_setlinesolver(nonogram_solver *c,
                           nonogram_level lvl, const char *n,
                           const struct nonogram_linesuite *s, void *conf)
{
  if (c->puzzle) return -1;
  if (lvl < 1 || lvl > c->levels) return -1;
  c->linesolver[lvl - 1].suite = s;
  c->linesolver[lvl - 1].context = conf;
  c->linesolver[lvl - 1].name = n;
  return 0;
}

static int nonogram_setlinesolvers(nonogram_solver *c, nonogram_level levels)
{
  struct nonogram_lsnt *tmp;

  if (c->puzzle) return -1;
  tmp = realloc(c->linesolver, sizeof(struct nonogram_lsnt) * levels);
  if (!tmp) return -1;
  c->linesolver = tmp;
  while (c->levels < levels)
    c->linesolver[c->levels++].suite = 0;
  c->levels = levels;
  return 0;
}



int nonogram_initsolver(nonogram_solver *c)
{
  /* these can get stuffed; nah, maybe not */
  c->reversed = false;
  c->first = nonogram_SOLID;
  c->cycles = 50;

  /* no puzzle loaded */
  c->puzzle = NULL;

  /* no display */
  c->display = NULL;

  /* no place to send solutions */
  c->client = NULL;



  /* no internal workspace */
  c->work = NULL;
  c->rowattr = c->colattr = NULL;
  c->rowflag = c->colflag = NULL;
  c->stack = NULL;

  /* start with no linesolvers */
  c->levels = 0;
  c->linesolver = NULL;
  c->workspace.byte = NULL;
  c->workspace.ptrdiff = NULL;
  c->workspace.size = NULL;
  c->workspace.nonogram_size = NULL;
  c->workspace.cell = NULL;

  /* then add the default */
  nonogram_setlinesolvers(c, 1);
  nonogram_setlinesolver(c, 1, "fcomp", &nonogram_fcompsuite, 0);

  c->focus = false;

  return 0;
}

int nonogram_termsolver(nonogram_solver *c)
{
  /* ensure a current puzzle and linesolver are removed */
  nonogram_unload(c);

  /* release all workspace */
  /* free(NULL) should be safe */
  free(c->workspace.byte);
  free(c->workspace.ptrdiff);
  free(c->workspace.size);
  free(c->workspace.nonogram_size);
  free(c->workspace.cell);
  free(c->rowflag);
  free(c->colflag);
  free(c->rowattr);
  free(c->colattr);
  free(c->work);
  return 0;
}

int nonogram_unload(nonogram_solver *c)
{
  nonogram_stack *st = c->stack;

  /* cancel current linesolver */
  if (c->puzzle)
    switch (c->status) {
    case nonogram_DONE:
    case nonogram_WORKING:
      if (c->linesolver[c->level].suite->term)
	(*c->linesolver[c->level].suite->term)
	  (c->linesolver[c->level].context);
      break;
    }

  /* free stack */
  while (st) {
    c->stack = st->next;
    free(st->grid);
    free(st->rowattr);
    free(st->colattr);
    free(st);
    st = c->stack;
  }
  c->focus = false;
  c->puzzle = NULL;
  return 0;
}

static void gathersolvers(nonogram_solver *c);

int nonogram_load(nonogram_solver *c, const nonogram_puzzle *puzzle,
		  nonogram_cell *grid, int remcells)
{
  /* local iterators */
  size_t lineno;

  /* is there already a puzzle loaded */
  if (c->puzzle)
    return -1;

  c->puzzle = puzzle;

  c->lim.maxline =
    (puzzle->width > puzzle->height) ? puzzle->width : puzzle->height;
  c->lim.maxrule = 0;

  /* initialise the grid */
  c->grid = grid;
  c->remcells = remcells;

  /* working data */
  free(c->work);
  free(c->rowflag);
  free(c->colflag);
  free(c->rowattr);
  free(c->colattr);
  c->work = malloc(sizeof(nonogram_cell) * c->lim.maxline);
  c->rowflag = malloc(sizeof(nonogram_level) * puzzle->height);
  c->colflag = malloc(sizeof(nonogram_level) * puzzle->width);
  c->rowattr = malloc(sizeof(nonogram_lineattr) * puzzle->height);
  c->colattr = malloc(sizeof(nonogram_lineattr) * puzzle->width);
  c->reminfo = 0;
  c->stack = NULL;

  /* determine heuristic scores for each column */
  for (lineno = 0; lineno < puzzle->width; lineno++) {
    struct nonogram_rule *rule = puzzle->col + lineno;

    c->reminfo += !!(c->colflag[lineno] = c->levels);

    if (rule->len > c->lim.maxrule)
      c->lim.maxrule = rule->len;

    makescore(c->colattr + lineno, rule, puzzle->height);
  }

  /* determine heuristic scores for each row */
  for (lineno = 0; lineno < puzzle->height; lineno++) {
    struct nonogram_rule *rule = puzzle->row + lineno;

    c->reminfo += !!(c->rowflag[lineno] = c->levels);

    if (rule->len > c->lim.maxrule)
      c->lim.maxrule = rule->len;

    makescore(c->rowattr + lineno, rule, puzzle->width);
  }

  gathersolvers(c);

  /* configure line solver */
  c->status = nonogram_EMPTY;

  return 0;
}

static void colfocus(nonogram_solver *c, int lineno, int v);
static void rowfocus(nonogram_solver *c, int lineno, int v);
static void mark1col(nonogram_solver *c, int lineno);
static void mark1row(nonogram_solver *c, int lineno);

static void makeguess(nonogram_solver *c);
static void findminrect(nonogram_solver *c, struct nonogram_rect *b);
static void findeasiest(nonogram_solver *c);

int nonogram_testtries(void *vt)
{
  int *tries = vt;
  return (*tries)-- > 0;
}

int nonogram_testtime(void *vt)
{
  const clock_t *t = vt;
  return clock() < *t;
}

int nonogram_runsolver_n(nonogram_solver *c, int *tries)
{
  int cy = c->cycles;
  int r = nonogram_runlines_tries(c, tries, &cy);
  return r == nonogram_LINE ? nonogram_UNFINISHED : r;
}

int nonogram_runlines(nonogram_solver *, int *, int (*)(void *), void *);

int nonogram_runlines_tries(nonogram_solver *c, int *lines, int *cycles)
{
  return nonogram_runlines(c, lines, &nonogram_testtries, cycles);
}

int nonogram_runlines_until(nonogram_solver *c, int *lines, clock_t lim)
{
  return nonogram_runlines(c, lines, &nonogram_testtime, &lim);
}

int nonogram_runcycles(nonogram_solver *c, int (*test)(void *), void *data);

int nonogram_runlines(nonogram_solver *c, int *lines,
                      int (*test)(void *), void *data)
{
  int r = c->puzzle ? nonogram_UNFINISHED : nonogram_UNLOADED;

  while (*lines > 0) {
    if ((r = nonogram_runcycles(c, test, data)) == nonogram_LINE)
      --*lines;
    else
      return r;
  }
  return r;
}

int nonogram_runcycles_tries(nonogram_solver *c, int *cycles)
{
  return nonogram_runcycles(c, (int (*)(void *)) &nonogram_testtries, cycles);
}

int nonogram_runcycles_until(nonogram_solver *c, clock_t lim)
{
  return nonogram_runcycles(c, (int (*)(void *)) &nonogram_testtime, &lim);
}

int nonogram_runcycles(nonogram_solver *c, int (*test)(void *), void *data)
{
  if (!c->puzzle) {
    return nonogram_UNLOADED;
  } else if (c->status == nonogram_WORKING) {
    /* in the middle of solving a line */
    while ((*test)(data) && c->status == nonogram_WORKING)
      step(c);
    return nonogram_UNFINISHED;
  } else if (c->status == nonogram_DONE)  {
    /* a line is solved, but not acted upon */
    size_t linelen;

    /* indicate end of line-processing */
    if (c->on_row)
      rowfocus(c, c->lineno, false), linelen = c->puzzle->width;
    else
      colfocus(c, c->lineno, false), linelen = c->puzzle->height;


    /* test for consistency */
    if (c->fits == 0) {
      /* nothing fitted; must be an error */
      c->remcells = -1;
    } else {
      int changed;


      /* update display and count number of changed cells and flags */
      changed = redeemstep(c);

      /* indicate choice to display */
      if (c->on_row) {
	if (c->rowattr[c->lineno].dot == 0 &&
	    c->rowattr[c->lineno].solid == 0)
	  c->rowflag[c->lineno] = 0;
	else if (c->fits < 0 && changed)
	  c->rowflag[c->lineno] = c->levels;
	else
	  --c->rowflag[c->lineno];
	if (!c->rowflag[c->lineno]) c->reminfo--;
	mark1row(c, c->lineno);
      } else {
	if (c->colattr[c->lineno].dot == 0 &&
	    c->colattr[c->lineno].solid == 0)
	  c->colflag[c->lineno] = 0;
	else if (c->fits < 0 && changed)
	  c->colflag[c->lineno] = c->levels;
	else
	  --c->colflag[c->lineno];
	if (!c->colflag[c->lineno]) c->reminfo--;
	mark1col(c, c->lineno);
      }
    }


    /* set state to indicate no line currently chosen */
    c->status = nonogram_EMPTY;
    return nonogram_LINE;
  } else if (c->remcells < 0) {
    /* back-track caused by error or completion of grid */
    nonogram_stack *st = c->stack;

    if (st) {
      size_t y, w;

      /* copy from stack */
      c->remcells = st->remcells;
      c->reminfo = 0;



      w = st->editarea.max.x - st->editarea.min.x;
      for (y = st->editarea.min.y; y < st->editarea.max.y; y++)
        memcpy(c->grid + st->editarea.min.x + y * c->puzzle->width,
               st->grid + (y - st->editarea.min.y) * w, w);

      /* update screen with restored data */
      ///if (c->display && c->display->redrawarea)  (*c->display->redrawarea)(c->display_data, &st->editarea);
      /* mark rows and cols (from st->editarea) as unflagged */
      c->reversed = false;
      for (y = st->editarea.min.x; y < st->editarea.max.x; y++) {
        c->colflag[y] = false;

        /* also restore scores */
        c->colattr[y] = st->colattr[y - st->editarea.min.x];
      }
      ///if (c->display && c->display->colmark)  (*c->display->colmark)(c->display_data, st->editarea.min.x, st->editarea.max.x);
      for (y = st->editarea.min.y; y < st->editarea.max.y; y++) {
        c->rowflag[y] = false;

        /* also restore scores */
        c->rowattr[y] = st->rowattr[y - st->editarea.min.y];
      }
      /// if (c->display && c->display->rowmark)        (*c->display->rowmark)(c->display_data,st->editarea.min.y, st->editarea.max.y);

      if (~st->level & nonogram_BOTH) {
        /* make subsequent guess */
        makeguess(c);
      } else {
        /* pull from stack */

        c->stack = st->next;
        free(st->grid);
        free(st->rowattr);
        free(st->colattr);
        free(st);
        c->remcells = -1;
      }
      return nonogram_LINE;
      /* finished loading from stack */
    } else {
      /* nothing left on stack - stop */
      return nonogram_FINISHED;
    }
    /* back-tracking dealt with */
  } else if (c->reminfo > 0) {
    /* no errors, but there are still lines to test */
    findeasiest(c);

    /* set up context for solving a row or column */
    if (c->on_row) {

      c->editarea.max.y = (c->editarea.min.y = c->lineno) + 1;
      rowfocus(c, c->lineno, true);
    } else {

      c->editarea.max.x = (c->editarea.min.x = c->lineno) + 1;
      colfocus(c, c->lineno, true);
    }
    setupstep(c);
    /* a line still to be tested has now been set up for solution */
    return nonogram_UNFINISHED;
  } else if (c->remcells == 0) {
    /* no remaining lines or cells; no error - must be solution */

    /// if (c->client && c->client->present) (*c->client->present)(c->client_data);

    c->remcells = -1;
    return c->stack ? nonogram_FOUND : nonogram_FINISHED;
  } else {
    /* no more info; no errors; some cells left
       - push stack to make a guess */
    nonogram_stack *st;
    size_t x, y, w, h;

    /* record the current state */
    /* create and insert new stack element */

    st = malloc(sizeof(nonogram_stack));
    st->next = c->stack;
    c->stack = st;
    st->remcells = c->remcells;
    st->level = nonogram_BLANK;

    /* find area to be recorded */
#if nonogram_PUSHALL
    /* COP-OUT: just use whole area */
    st->editarea.min.x = st->editarea.min.y = 0;
    st->editarea.max.x = c->puzzle->width;
    st->editarea.max.y = c->puzzle->height;
#else
    /* be more selective */
    findminrect(c, &st->editarea);
#endif
    w = st->editarea.max.x - st->editarea.min.x;
    h = st->editarea.max.y - st->editarea.min.y;


    /* copy specified area */
    st->grid = malloc(w * h * sizeof(nonogram_cell));
    for (y = st->editarea.min.y; y < st->editarea.max.y; y++)
      memcpy(st->grid + (y - st->editarea.min.y) * w,
             c->grid + st->editarea.min.x + y * c->puzzle->width, w);

    /* copy scores */
    st->rowattr = malloc(h * sizeof(nonogram_lineattr));
    st->colattr = malloc(w * sizeof(nonogram_lineattr));
    for (y = st->editarea.min.y; y < st->editarea.max.y; y++)
      st->rowattr[y - st->editarea.min.y] = c->rowattr[y];
    for (x = st->editarea.min.x; x < st->editarea.max.x; x++)
      st->colattr[x - st->editarea.min.x] = c->colattr[x];

    /* choose position to make guess */
#if 0
    for (x = st->editarea.min.x; x < st->editarea.max.x; x++)
      for (y = st->editarea.min.y; y < st->editarea.max.y; y++)
	if (c->grid[x + y * c->puzzle->width] == nonogram_BLANK)
	  goto found;
  found:
    st->pos.x = x;
    st->pos.y = y;
#else
    {
      int bestscore = -1000;
      for (x = st->editarea.min.x; x < st->editarea.max.x; x++)
	for (y = st->editarea.min.y; y < st->editarea.max.y; y++)
	  if (c->grid[x + y * c->puzzle->width] == nonogram_BLANK) {
	    int score = c->rowattr[y].score + c->colattr[x].score;
	    if (score < bestscore)
	      continue;
	    bestscore = score;
	    st->pos.x = x;
	    st->pos.y = y;
	  }
    }
#endif

    makeguess(c);
    return nonogram_LINE;
  }

  return nonogram_UNFINISHED;
}

static void makeguess(nonogram_solver *c)
{
  nonogram_stack *st = c->stack;
  int guess;

  if (!st) return;

#if false
#if 0
  /* make guess */
  guess = st->level ? (nonogram_BOTH ^ st->level): c->first;
#else
  /* hard-wired first choice */
#if 1
  /* dot first */
  guess = (st->level & nonogram_DOT) ? nonogram_SOLID : nonogram_DOT;
#else
  /* solid first */
  guess = (st->level & nonogram_SOLID) ? nonogram_DOT : nonogram_SOLID;
#endif
#endif
#else
  /* guess base on majority of unaccounted cells */
  guess = st->level ? (nonogram_BOTH ^ st->level) :
    (c->rowattr[st->pos.y].dot + c->colattr[st->pos.x].dot >
     c->rowattr[st->pos.y].solid + c->colattr[st->pos.x].solid ?
     nonogram_DOT : nonogram_SOLID);
#endif


  c->grid[st->pos.x + st->pos.y * c->puzzle->width] = guess;

  /* update score for row */
  if (!--*(guess == nonogram_DOT ?
           &c->rowattr[st->pos.y].dot : &c->rowattr[st->pos.y].solid))
    c->rowattr[st->pos.y].score = c->puzzle->height;
  else
    c->rowattr[st->pos.y].score++;

  /* update score for column */
  if (!--*(guess == nonogram_DOT ?
           &c->colattr[st->pos.x].dot : &c->colattr[st->pos.x].solid))
    c->colattr[st->pos.x].score = c->puzzle->width;
  else
    c->colattr[st->pos.x].score++;

  st->level |= guess;
  c->remcells--;
  c->reminfo = 2;

  c->rowflag[st->pos.y] = c->levels;
  c->colflag[st->pos.x] = c->levels;
  mark1row(c, st->pos.y);
  mark1col(c, st->pos.x);
#if 0
  ///
  if (c->display && c->display->redrawarea) {
    struct nonogram_rect gp;
    gp.max.x = (gp.min.x = st->pos.x) + 1;
    gp.max.y = (gp.min.y = st->pos.y) + 1;
    (*c->display->redrawarea)(c->display_data, &gp);
  }
#endif
}

/* This sets the rectangle *b to the smallest inclusive rectangle that
 * covers all the unknown cells. */
static void findminrect(nonogram_solver *c, struct nonogram_rect *b)
{
  int m = c->puzzle->width * c->puzzle->height;
  int first = 0, last = m - 1;
  size_t x, y;

  if (c->puzzle->width == 0 || c->puzzle->height == 0) {
    b->min.x = b->min.y = 0;
    b->max.x = c->puzzle->width;
    b->max.y = c->puzzle->height;
    return;
  }

  while (first < m && c->grid[first] != nonogram_BLANK)
    first++;
  b->min.x = first % c->puzzle->width;
  b->min.y = first / c->puzzle->width;
  for (y = b->min.y + 1; y < c->puzzle->height; y++) {
    for (x = 0; x < b->min.x &&
         c->grid[x + y * c->puzzle->width] != nonogram_BLANK; x++)
      ;
    b->min.x = x;
  }

  while (last >= first && c->grid[last] != nonogram_BLANK)
    last--;
  b->max.x = last % c->puzzle->width + 1;
  b->max.y = last / c->puzzle->width + 1;
  for (y = b->max.y; y > b->min.y; ) {
    y--;
    for (x = c->puzzle->width; x > b->max.x; ) {
      x--;
      if (c->grid[x + y * c->puzzle->width] == nonogram_BLANK) {
	x++;
	break;
      }
    }
    b->max.x = x;
  }

}

static void findeasiest(nonogram_solver *c)
{
  int score;
  size_t i;

  c->level = c->rowflag[0];
  score = c->rowattr[0].score;
  c->on_row = true;
  c->lineno = 0;

  for (i = 0; i < c->puzzle->height; i++)
    if (c->rowflag[i] > c->level ||
	(c->level > 0 && c->rowflag[i] == c->level &&
	 c->rowattr[i].score > score)) {
      c->level = c->rowflag[i];
      score = c->rowattr[i].score;
      c->lineno = i;
    }

  for (i = 0; i < c->puzzle->width; i++)
    if (c->colflag[i] > c->level ||
	(c->level > 0 && c->colflag[i] == c->level &&
	 c->colattr[i].score > score)) {
      c->level = c->colflag[i];
      score = c->colattr[i].score;
      c->lineno = i;
      c->on_row = false;
    }
}

static void makescore(nonogram_lineattr *attr,
		      const struct nonogram_rule *rule, int len)
{
  size_t relem;

  attr->score = 0;
  for (relem = 0; relem < rule->len; relem++)
    attr->score += rule->val[relem];
  attr->dot = len - (attr->solid = attr->score);
  if (!attr->solid)
    attr->score = len;
  else {
    attr->score *= rule->len + 1;
    attr->score += rule->len * (rule->len - len - 1);
  }
}

static void colfocus(nonogram_solver *c, int lineno, int v)
{
  c->focus = v;
  ///if (c->display && c->display->colfocus)  (*c->display->colfocus)(c->display_data, lineno, v);
}

static void rowfocus(nonogram_solver *c, int lineno, int v)
{
  c->focus = v;
  ///  if (c->display && c->display->rowfocus)    (*c->display->rowfocus)(c->display_data, lineno, v);
}

static void mark1col(nonogram_solver *c, int lineno)
{
  ///  if (c->display && c->display->colmark)    (*c->display->colmark)(c->display_data, lineno, lineno + 1);
}

static void mark1row(nonogram_solver *c, int lineno)
{
  ///  if (c->display && c->display->rowmark)    (*c->display->rowmark)(c->display_data, lineno, lineno + 1);
}

static void gathersolvers(nonogram_solver *c)
{
  static struct nonogram_req zero;
  struct nonogram_req most = zero, req;
  nonogram_level n;

  for (n = 0; n < c->levels; n++)
    if (c->linesolver[n].suite && c->linesolver[n].suite->prep) {
      req = zero;
      (*c->linesolver[n].suite->prep)(c->linesolver[n].context, &c->lim, &req);
      if (req.byte > most.byte)
	most.byte = req.byte;
      if (req.ptrdiff > most.ptrdiff)
	most.ptrdiff = req.ptrdiff;
      if (req.size > most.size)
	most.size = req.size;
      if (req.nonogram_size > most.nonogram_size)
	most.nonogram_size = req.nonogram_size;
      if (req.cell > most.cell)
	most.cell = req.cell;
    }

  free(c->workspace.byte);
  free(c->workspace.ptrdiff);
  free(c->workspace.size);
  free(c->workspace.nonogram_size);
  free(c->workspace.cell);
  c->workspace.byte = malloc(most.byte);
  c->workspace.ptrdiff = malloc(most.ptrdiff * sizeof(ptrdiff_t));
  c->workspace.size = malloc(most.size * sizeof(size_t));
  c->workspace.nonogram_size =
    malloc(most.nonogram_size * sizeof(nonogram_sizetype));
  c->workspace.cell = malloc(most.cell * sizeof(nonogram_cell));
}


static void redrawrange(nonogram_solver *c, int from, int to);
static void mark(nonogram_solver *c, int from, int to);

static void setupstep(nonogram_solver *c)
{
  struct nonogram_initargs a;
  const char *name;

  if (c->on_row) {
    a.line = c->grid + c->puzzle->width * c->lineno;
    a.linelen = c->puzzle->width;
    a.linestep = 1;
    a.rule = c->puzzle->row[c->lineno].val;
    a.rulelen = c->puzzle->row[c->lineno].len;
  } else {
    a.line = c->grid + c->lineno;
    a.linelen = c->puzzle->height;
    a.linestep = c->puzzle->width;
    a.rule = c->puzzle->col[c->lineno].val;
    a.rulelen = c->puzzle->col[c->lineno].len;
  }
  a.rulestep = 1;
  a.fits = &c->fits;
  ///  a.log = &c->tmplog;
  a.result = c->work;
  a.resultstep = 1;

  c->reversed = false;

  if (c->level > c->levels || c->level < 1 ||
      !c->linesolver[c->level - 1].suite ||
      !c->linesolver[c->level - 1].suite->init)
    name = "backup";
  else
    name = c->linesolver[c->level - 1].name ?
      c->linesolver[c->level - 1].name : "unknown";


  /* implement a backup solver */
  if (c->level > c->levels || c->level < 1 ||
      !c->linesolver[c->level - 1].suite ||
      !c->linesolver[c->level - 1].suite->init) {
    size_t i;

    /* reveal nothing */
    for (i = 0; i < a.linelen; i++)
      switch (a.line[i * a.linestep]) {
      case nonogram_DOT:
      case nonogram_SOLID:
	c->work[i] = a.line[i * a.linestep];
	break;
      default:
	c->work[i] = nonogram_BOTH;
	break;
      }

    c->status = nonogram_DONE;
    return;
  }

  c->status =
    (*c->linesolver[c->level - 1].suite->init)
    (c->linesolver[c->level - 1].context, &c->workspace, &a) ?
    nonogram_WORKING : nonogram_DONE;
}

static void step(nonogram_solver *c)
{
  if (c->level > c->levels || c->level < 1 ||
      !c->linesolver[c->level - 1].suite ||
      !c->linesolver[c->level - 1].suite->step) {
    size_t i, linelen = c->on_row ? c->puzzle->width : c->puzzle->height;
    ptrdiff_t linestep = c->on_row ? 1 : c->puzzle->width;
    const nonogram_cell *line =
      c->on_row ? c->grid + c->puzzle->width * c->lineno : c->grid + c->lineno;

    /* reveal nothing */
    for (i = 0; i < linelen; i++)
      switch (line[i * linestep]) {
      case nonogram_DOT:
      case nonogram_SOLID:
	c->work[i] = line[i * linestep];
	break;
      default:
	c->work[i] = nonogram_BOTH;
	break;
      }

    c->status = nonogram_DONE;
    return;
  }

  c->status = (*c->linesolver[c->level - 1].suite->step)
    (c->linesolver[c->level - 1].context, c->workspace.byte) ?
    nonogram_WORKING : nonogram_DONE;
}

static int redeemstep(nonogram_solver *c)
{
  int changed = 0;
  nonogram_cell *line;
  nonogram_sizetype *rule;
  size_t linelen, rulelen, perplen;
  ptrdiff_t linestep, flagstep, rulestep;
  nonogram_lineattr *attr, *rattr, *cattr;
  nonogram_level *flag;

  size_t i;

  struct {
    int from;
    unsigned inrange : 1;
  } cells = { 0, false }, flags = { 0, false };

  if (c->on_row) {
    line = c->grid + c->puzzle->width * c->lineno;
    linelen = c->puzzle->width;
    linestep = 1;
    rule = c->puzzle->row[c->lineno].val;
    rulelen = c->puzzle->row[c->lineno].len;
    rulestep = 1;
    perplen = c->puzzle->height;
    rattr = c->colattr;
    cattr = c->rowattr + c->lineno;
    flag = c->colflag;
    flagstep = 1;
  } else {
    line = c->grid + c->lineno;
    linelen = c->puzzle->height;
    linestep = c->puzzle->width;
    rule = c->puzzle->col[c->lineno].val;
    rulelen = c->puzzle->col[c->lineno].len;
    rulestep = 1;
    perplen = c->puzzle->width;
    cattr = c->colattr + c->lineno;
    rattr = c->rowattr;
    flag = c->rowflag;
    flagstep = 1;
  }

  for (i = 0; i < linelen; i++)
    switch (line[i * linestep]) {
    case nonogram_BLANK:
      switch (c->work[i]) {
      case nonogram_DOT:
      case nonogram_SOLID:
	changed = 1;
        if (!cells.inrange) {
          cells.from = i;
          cells.inrange = true;
        }
        line[i * linestep] = c->work[i];
        c->remcells--;

        /* update score for perpendicular line */
        attr = &rattr[i * flagstep];
        if (!--*(c->work[i] == nonogram_DOT ?
                 &attr->dot : &attr->solid))
          attr->score = perplen;
        else
          attr->score++;

        /* update score for solved line */
        if (!--*(c->work[i] == nonogram_DOT ? &cattr->dot : &cattr->solid))
          cattr->score = linelen;
        else
          cattr->score++;

        if (flag[i * flagstep] < c->levels) {
          if (flag[i * flagstep] == 0) c->reminfo++;
          flag[i * flagstep] = c->levels;

          if (!flags.inrange) {
            flags.from = i;
            flags.inrange = true;
          }
        } else if (flags.inrange) {
          mark(c, flags.from, i);
          flags.inrange = false;
        }
        break;
      }
      break;
    default:
      if (cells.inrange) {
        redrawrange(c, cells.from, i);
        cells.inrange = false;
      }
      if (flags.inrange) {
        mark(c, flags.from, i);
        flags.inrange = false;
      }
      break;
    }
  if (cells.inrange) {
    redrawrange(c, cells.from, i);
    cells.inrange = false;
  }
  if (flags.inrange) {
    mark(c, flags.from, i);
    flags.inrange = false;
  }

  if (c->level <= c->levels && c->level > 0 &&
      c->linesolver[c->level - 1].suite &&
      c->linesolver[c->level - 1].suite->term)
    (*c->linesolver[c->level - 1].suite->term)
      (c->linesolver[c->level - 1].context);

  return changed;
}

static void mark(nonogram_solver *c, int from, int to)
{
#if 0
  ///
  if (c->display) {
    if (c->on_row) {
      if (c->display->colmark) {
        if (c->reversed) {
          int temp = c->puzzle->height - from;
          from = c->puzzle->height - to;
          to = temp;
        }
        (*c->display->colmark)(c->display_data, from, to);
      }
    } else {
      if (c->display->rowmark) {
        if (c->reversed) {
          int temp = c->puzzle->width - from;
          from = c->puzzle->width - to;
          to = temp;
        }
        (*c->display->rowmark)(c->display_data, from, to);
      }
    }
  }
#endif
}

static void redrawrange(nonogram_solver *c, int from, int to)
{
  ///  if (!c->display || !c->display->redrawarea) return;


  if (c->on_row) {
    if (c->reversed) {
      c->editarea.max.x = c->puzzle->width - from;
      c->editarea.min.x = c->puzzle->width - to;
    } else {
      c->editarea.min.x = from;
      c->editarea.max.x = to;
    }
  } else {
    if (c->reversed) {
      c->editarea.max.y = c->puzzle->height - from;
      c->editarea.min.y = c->puzzle->height - to;
    } else {
      c->editarea.min.y = from;
      c->editarea.max.y = to;
    }
  }

  ///  (*c->display->redrawarea)(c->display_data, &c->editarea);

}

const char *const nonogram_date = __DATE__;
