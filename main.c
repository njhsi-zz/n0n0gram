#include "nonogram.h"

/* make puzzle */
static int make_puzzle(nonogram_puzzle *p)
{

  p->width = 5;
  p->height = 5;

  p->row = (struct nonogram_rule*) malloc(p->height * sizeof(struct nonogram_rule));
  p->col = (struct nonogram_rule*) malloc(p->width * sizeof(struct nonogram_rule));

  for (int i=0; i<p->width; i++){
    p->row[i].len = 1;
    p->row[i].val = (nonogram_sizetype*)malloc( p->row[i].len * sizeof(nonogram_sizetype) );
    
    p->row[i].val[0] = p->width;
  }

  for (int i=0; i<p->height; i++){
    p->col[i].len = 1;
    p->col[i].val = (nonogram_sizetype*)malloc( p->col[i].len * sizeof(nonogram_sizetype) );
    
    p->col[i].val[0] = p->height;
  }


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


  make_puzzle(&p);

  // set the result grid
  nonogram_cell* g = (nonogram_cell*)malloc(p.width*p.height*sizeof(nonogram_cell)) ;

  nonogram_solver c;

  //1. verify the puzzle 
  int i = verify_puzzle(&p);
  printf("verify:%d\n",i);

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
