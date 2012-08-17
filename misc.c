#include "nonogram.h"


static int nonogram_parseline(const nonogram_cell *st,
			      size_t len, ptrdiff_t step,
			      nonogram_sizetype *v, ptrdiff_t vs)
{
  size_t i;
  int count = 0;
  int inblock = false;

  for (i = 0; i < len; i++)
    switch (st[i * step]) {
    case nonogram_DOT:
      if (inblock) {
	inblock = false;
	count++;
      }
      break;
    case nonogram_SOLID:
      if (!inblock) {
	inblock = true;
	if (v)
	  v[count * vs] = 0;
      }
      if (v)
	v[count * vs]++;
      break;
    default:
      return -1;
    }
  return count + !!inblock;
}

int nonogram_makepuzzle(nonogram_puzzle *p, const nonogram_cell *g,
			size_t w, size_t h)
{
  size_t n;

  if (!p || !g) return -1;

  p->width = w;
  p->height = h;

  p->row = malloc(sizeof(struct nonogram_rule) * h);
  p->col = malloc(sizeof(struct nonogram_rule) * w);

  if (!p->row || !p->col)
    goto failure;

  for (n = 0; n < h; n++) {
    int rc = nonogram_parseline(g + w * n, w, 1, NULL, 0);
    if (rc < 0)
      goto failure;
    p->row[n].len = rc;
    p->row[n].val = NULL;
  }
  for (n = 0; n < w; n++) {
    int rc = nonogram_parseline(g + n, h, w, NULL, 0);
    if (rc < 0)
      goto failure;
    p->col[n].len = rc;
    p->col[n].val = NULL;
  }
  for (n = 0; n < h; n++) {
    struct nonogram_rule *rule = &p->row[n];
    rule->val = malloc(sizeof(nonogram_sizetype) * rule->len);
    if (!rule->val)
      goto worse;
    nonogram_parseline(g + w * n, w, 1, rule->val, 1);
  }
  for (n = 0; n < w; n++) {
    struct nonogram_rule *rule = &p->col[n];
    rule->val = malloc(sizeof(nonogram_sizetype) * rule->len);
    if (!rule->val)
      goto worse;
    nonogram_parseline(g + n, h, w, rule->val, 1);
  }
  return 0;

worse:
  for (n = 0; n < h; n++)
    free(p->row[n].val);
  for (n = 0; n < w; n++)
    free(p->col[n].val);
failure:
  free(p->row);
  free(p->col);
  return -1;
}

 nonogram_cell *loadgrid(size_t *width, size_t *height,
			  FILE *fp, char solid, char dot)
{
  struct line {
    struct line *prev;
    nonogram_cell *data;
  };

  char temp[300];
  nonogram_cell *result;
  size_t len, i;
  struct line *bottom;

  if (!width || !height) return NULL;
  bottom = NULL;
  *width = 0;
  *height = 0;

  while (fgets(temp, sizeof temp, fp)) {
    struct line *next;

    len = strlen(temp);
    if (len > 0 && temp[len - 1] == '\n')
      temp[--len] = '\0';

    if (*width < 1) {
      *width = len;
    } else if (len != *width) {
      goto finished;
    }

    next = malloc(sizeof(struct line));
    if (!next)
      goto failure;
    next->data = malloc(*width * sizeof(nonogram_cell));
    if (!next->data)
      goto failure;
    for (i = 0; i < *width; i++)
      next->data[i] = temp[i] == dot ? nonogram_DOT :
      (temp[i] == solid ? nonogram_SOLID : nonogram_BLANK);
    next->prev = bottom;
    bottom = next;
    (*height)++;
  }

finished:
  result = nonogram_makegrid(*width, *height);
  if (!result)
    goto failure;

  for (i = *height; i > 0; ) {
    struct line *prev = bottom->prev;
    i--;
    memcpy(result + i * *width, bottom->data, *width);
    free(bottom->data);
    free(bottom);
    bottom = prev;
  }

  return result;

failure:
  while (bottom) {
    struct line *prev = bottom->prev;
    free(bottom->data);
    free(bottom);
    bottom = prev;
  }

  return NULL;
}
