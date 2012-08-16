#include "nonogram.h"

/* make puzzle */
static int make_puzzle(nonogram_puzzle *p)
{

  return 0;
}

/*verify puzzle*/
int verify_puzzle(const nonogram_puzzle *p)
{
  int sum = 0;
  size_t lineno, relno;

  for (lineno = 0; lineno < p->height; lineno++)
    for (relno = 0; relno < p->row[lineno].len; relno++)
      sum += p->row[lineno].val[relno];

  for (lineno = 0; lineno < p->width; lineno++)
    for (relno = 0; relno < p->col[lineno].len; relno++)
      sum -= p->col[lineno].val[relno];

  return sum;
}


int main()
{
  // set the puzzle
  nonogram_puzzle p;

  // set the result grid
  nonogram_cell* g;

  nonogram_solver c;

  //1. verify the puzzle 

  // 2. 
  nonogram_initsolver(&c);
  //  nonogram_setalgo(&handle.solver, c->algo);
  //  nonogram_setlog(&handle.solver, handle.logfp, 0, c->loglevel);
  //  nonogram_setclient(&handle.solver, &our_client, &handle);

  /* now load the puzzle after configuration */
  nonogram_load(&c, &p, g,
                nonogram_puzzlewidth(&p) *
                nonogram_puzzleheight(&p));

  int bstop = false;
  int tries;
  while (!bstop &&
	 nonogram_runsolver_n(&c,
			      (tries = 1, &tries)) != nonogram_FINISHED)
    ;

    nonogram_termsolver(&c);
  //  nonogram_freegrid(g);



  return 0;
}
